/*
 * Copyright 2023-2026 Michael Büchner, Deutsche Digitale Bibliothek
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package de.ddb.labs.iiif;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.PushbackReader;
import java.io.Reader;
import java.net.InetAddress;
import java.net.Proxy;
import java.net.URI;
import java.net.UnknownHostException;
import java.nio.charset.Charset;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.List;
import java.util.regex.Pattern;
import javax.xml.XMLConstants;
import javax.xml.parsers.ParserConfigurationException;
import javax.xml.parsers.SAXParserFactory;
import javax.xml.transform.sax.SAXSource;
import net.sf.saxon.Configuration;
import net.sf.saxon.lib.ResourceRequest;
import net.sf.saxon.lib.ResourceResolver;
import net.sf.saxon.lib.UnparsedTextURIResolver;
import net.sf.saxon.trans.XPathException;
import okhttp3.Dns;
import okhttp3.HttpUrl;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.ResponseBody;
import org.xml.sax.InputSource;
import org.xml.sax.SAXException;
import org.xml.sax.XMLReader;

final class CustomResolver implements ResourceResolver, UnparsedTextURIResolver {

    private static final int MAX_RESOURCE_BYTES = 8 * 1024 * 1024;
    private static final int MAX_REDIRECTS = 5;
    private static final Duration FETCH_TIMEOUT = Duration.ofSeconds(15);
    private static final Pattern NUMERIC_HOST = Pattern.compile("[0-9.]+");
    private final OkHttpClient httpClient;
    private final Long transformationDeadline;

    CustomResolver(OkHttpClient baseClient) {
        this(baseClient.newBuilder()
                .dns(CustomResolver::publicAddresses)
                .proxy(Proxy.NO_PROXY)
                .followRedirects(false)
                .build(), null);
    }

    private CustomResolver(OkHttpClient httpClient, Long transformationDeadline) {
        this.httpClient = httpClient;
        this.transformationDeadline = transformationDeadline;
    }

    CustomResolver forTransformation(Duration timeBudget) {
        return new CustomResolver(httpClient, System.nanoTime() + timeBudget.toNanos());
    }

    @Override
    public SAXSource resolve(ResourceRequest request) throws XPathException {
        final RemoteResource resource = fetch(request.uri, "application/xml, text/xml");
        final InputSource source = new InputSource(new ByteArrayInputStream(resource.content()));
        source.setSystemId(resource.url().toString());
        return secureXmlSource(source);
    }

    @Override
    public Reader resolve(URI uri, String encoding, Configuration configuration, boolean fallback) throws XPathException {
        final RemoteResource resource = fetch(uri.toASCIIString(), "application/json");
        try {
            final Charset charset = encoding != null ? Charset.forName(encoding) : resource.charset();
            final CodingErrorAction action = fallback ? CodingErrorAction.REPLACE : CodingErrorAction.REPORT;
            final PushbackReader reader = new PushbackReader(new InputStreamReader(
                    new ByteArrayInputStream(resource.content()),
                    charset.newDecoder().onMalformedInput(action).onUnmappableCharacter(action)));
            final int firstCharacter = reader.read();
            if (firstCharacter != -1 && firstCharacter != '\uFEFF') {
                reader.unread(firstCharacter);
            }
            return reader;
        } catch (IOException | IllegalArgumentException e) {
            throw new XPathException("Could not decode remote IIIF metadata", e);
        }
    }

    static SAXSource secureXmlSource(InputSource source) throws XPathException {
        try {
            final SAXParserFactory factory = SAXParserFactory.newDefaultNSInstance();
            factory.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
            factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
            final XMLReader reader = factory.newSAXParser().getXMLReader();
            reader.setProperty(XMLConstants.ACCESS_EXTERNAL_DTD, "");
            reader.setProperty(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "");
            return new SAXSource(reader, source);
        } catch (ParserConfigurationException | SAXException e) {
            throw new XPathException("Could not initialize secure XML parsing", e);
        }
    }

    private RemoteResource fetch(String address, String accept) throws XPathException {
        final long now = System.nanoTime();
        final long fetchTimeout = transformationDeadline == null ? FETCH_TIMEOUT.toNanos()
                : Math.min(FETCH_TIMEOUT.toNanos(), transformationDeadline - now);
        if (fetchTimeout <= 0) {
            throw new XPathException("Remote IIIF metadata exceeded the transformation time budget");
        }

        HttpUrl url = address == null ? null : HttpUrl.parse(address);
        final long deadline = now + fetchTimeout;
        for (int redirects = 0; redirects <= MAX_REDIRECTS; redirects++) {
            validateUrl(url);
            final Request request = new Request.Builder().url(url).header("Accept", accept).build();
            final var call = httpClient.newCall(request);
            call.timeout().deadlineNanoTime(deadline);
            try (Response response = call.execute()) {
                if (response.isSuccessful()) {
                    return readResource(url, response.body());
                }

                final String location = response.header("Location");
                if (location == null || !isRedirect(response.code())) {
                    throw new XPathException("Remote IIIF metadata returned HTTP " + response.code());
                }
                url = url.resolve(location);
            } catch (IOException e) {
                throw new XPathException("Could not load remote IIIF metadata", e);
            }
        }
        throw new XPathException("Remote IIIF metadata exceeded the redirect limit");
    }

    private static boolean isRedirect(int status) {
        return switch (status) {
            case 300, 301, 302, 303, 307, 308 -> true;
            default -> false;
        };
    }

    private static void validateUrl(HttpUrl url) throws XPathException {
        if (url == null || !url.username().isEmpty() || !url.password().isEmpty()) {
            throw new XPathException("Remote IIIF metadata requires an HTTP(S) URL without credentials");
        }

        final String host = url.host();
        // OkHttp connects to numeric addresses without invoking the configured DNS resolver.
        if (host.indexOf(':') >= 0 || NUMERIC_HOST.matcher(host).matches()) {
            try {
                if (!isPublicAddress(InetAddress.ofLiteral(host))) {
                    throw new XPathException("Remote IIIF metadata requires a public address");
                }
            } catch (IllegalArgumentException e) {
                throw new XPathException("Invalid address for remote IIIF metadata", e);
            }
        }
    }

    private static RemoteResource readResource(HttpUrl url, ResponseBody body) throws IOException, XPathException {
        if (body == null || body.contentLength() > MAX_RESOURCE_BYTES) {
            throw new XPathException("Remote IIIF metadata is missing or exceeds the size limit");
        }

        final InputStream stream = body.byteStream();
        final byte[] content = stream.readNBytes(MAX_RESOURCE_BYTES + 1);
        if (content.length > MAX_RESOURCE_BYTES) {
            throw new XPathException("Remote IIIF metadata exceeds the size limit");
        }
        final MediaType mediaType = body.contentType();
        final Charset charset = mediaType == null ? StandardCharsets.UTF_8 : mediaType.charset(StandardCharsets.UTF_8);
        return new RemoteResource(content, url, charset);
    }

    private static List<InetAddress> publicAddresses(String host) throws UnknownHostException {
        final List<InetAddress> addresses = Dns.SYSTEM.lookup(host).stream()
                .filter(CustomResolver::isPublicAddress)
                .toList();
        if (addresses.isEmpty()) {
            throw new UnknownHostException("Remote IIIF metadata requires a public address");
        }
        return addresses;
    }

    static boolean isPublicAddress(InetAddress address) {
        if (address.isAnyLocalAddress() || address.isLoopbackAddress() || address.isLinkLocalAddress()
                || address.isSiteLocalAddress() || address.isMulticastAddress()) {
            return false;
        }

        final byte[] bytes = address.getAddress();
        final int first = Byte.toUnsignedInt(bytes[0]);
        final int second = Byte.toUnsignedInt(bytes[1]);
        final int third = Byte.toUnsignedInt(bytes[2]);
        if (bytes.length == 4) {
            // Exclude shared, special-purpose, documentation and reserved IPv4 ranges.
            return first != 0 && first < 224
                    && !(first == 100 && second >= 64 && second < 128)
                    && !(first == 192 && second == 0 && (third == 0 || third == 2))
                    && !(first == 192 && second == 88 && third == 99)
                    && !(first == 198 && (second == 18 || second == 19 || (second == 51 && third == 100)))
                    && !(first == 203 && second == 0 && third == 113);
        }

        // Use global unicast IPv6, excluding transition and special-purpose prefixes.
        return (first & 0xE0) == 0x20
                && !(first == 0x20 && second == 0x01 && (third <= 1 || (third == 0x0D && bytes[3] == (byte) 0xB8)))
                && !(first == 0x20 && second == 0x02)
                && !(first == 0x3F && second == 0xFF && (third & 0xF0) == 0);
    }

    private record RemoteResource(byte[] content, HttpUrl url, Charset charset) {}
}
