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

import jakarta.servlet.http.HttpServletRequest;
import java.io.IOException;
import java.io.InputStream;
import java.io.InterruptedIOException;
import java.io.StringReader;
import java.time.Duration;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Pattern;
import javax.xml.transform.stream.StreamSource;
import net.sf.saxon.s9api.DocumentBuilder;
import net.sf.saxon.s9api.Processor;
import net.sf.saxon.s9api.QName;
import net.sf.saxon.s9api.SaxonApiException;
import net.sf.saxon.s9api.XPathCompiler;
import net.sf.saxon.s9api.XPathExecutable;
import net.sf.saxon.s9api.XPathSelector;
import net.sf.saxon.s9api.XdmAtomicValue;
import net.sf.saxon.s9api.XdmDestination;
import net.sf.saxon.s9api.XdmItem;
import net.sf.saxon.s9api.XdmNode;
import net.sf.saxon.s9api.XsltCompiler;
import net.sf.saxon.s9api.XsltExecutable;
import net.sf.saxon.s9api.XsltTransformer;
import net.sf.saxon.trans.XPathException;
import okhttp3.HttpUrl;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.NestedExceptionUtils;
import org.springframework.core.io.ClassPathResource;
import org.springframework.core.io.InputStreamResource;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.util.FastByteArrayOutputStream;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.xml.sax.InputSource;

/**
 * Erzeugt Manifeste der IIIF Presentation API 3 aus DDB-Metadaten.
 * Die XPath-Ausdrücke und Stylesheets werden beim Start kompiliert und wiederverwendet.
 * Parser, XPath-Selektoren und Transformer entstehen pro Anfrage.
 */
@RestController
@CrossOrigin(origins = "*", allowedHeaders = "*", maxAge = 3600)
class IiifRestController {

    private static final Logger LOG = LoggerFactory.getLogger(IiifRestController.class);
    private static final Pattern DDB_ID = Pattern.compile("[A-Za-z2-7]{32}");
    private static final String METS_NAMESPACE = "http://www.loc.gov/METS/";

    private final OkHttpClient httpClient;
    private final CustomResolver resolver;
    private final String baseUrl;
    private final String ddbApiKeyProd;
    private final String ddbApiKeyQ1;
    private final String ddbApiKeyQ2;
    private final int maxMetadataBytes;
    private final int maxManifestBytes;
    private final Processor processor;
    private final XPathExecutable cortexRecord;
    private final XPathExecutable sourceRecord;
    private final XPathExecutable inlineMetadata;
    private final XPathExecutable oaiMetadata;
    private final XPathExecutable metsRecord;
    private final XPathExecutable providerInfo;
    private final XsltExecutable cortexToIiif;
    private final XsltExecutable xmlToJson;
    private final XsltExecutable metsmodsToIiif;

    @Autowired
    IiifRestController(
            @Value("${iiif.baseurl}") String baseUrl,
            @Value("${iiif.ddb_api_key_prod}") String ddbApiKeyProd,
            @Value("${iiif.ddb_api_key_q1}") String ddbApiKeyQ1,
            @Value("${iiif.ddb_api_key_q2}") String ddbApiKeyQ2,
            @Value("${iiif.max-metadata-bytes:67108864}") int maxMetadataBytes,
            @Value("${iiif.max-manifest-bytes:67108864}") int maxManifestBytes) throws IOException, SaxonApiException {
        this(baseUrl, ddbApiKeyProd, ddbApiKeyQ1, ddbApiKeyQ2, maxMetadataBytes, maxManifestBytes, new OkHttpClient.Builder()
                .connectTimeout(Duration.ofSeconds(5))
                .readTimeout(Duration.ofSeconds(10))
                .callTimeout(Duration.ofSeconds(30))
                // Verhindert, dass eine Weiterleitung die authentifizierte Anfrage an ein anderes Ziel lenkt.
                .followRedirects(false)
                .build());
    }

    IiifRestController(String baseUrl, String ddbApiKeyProd, String ddbApiKeyQ1, String ddbApiKeyQ2,
                       int maxMetadataBytes, int maxManifestBytes, OkHttpClient httpClient) throws IOException, SaxonApiException {
        if (maxMetadataBytes <= 0 || maxManifestBytes <= 0) {
            throw new IllegalArgumentException("Metadata and manifest size limits must be positive");
        }
        this.baseUrl = baseUrl.replaceFirst("/+$", "");
        this.ddbApiKeyProd = ddbApiKeyProd;
        this.ddbApiKeyQ1 = ddbApiKeyQ1;
        this.ddbApiKeyQ2 = ddbApiKeyQ2;
        this.maxMetadataBytes = maxMetadataBytes;
        this.maxManifestBytes = maxManifestBytes;
        this.httpClient = httpClient;
        resolver = new CustomResolver(httpClient);
        processor = new Processor(false);

        final XPathCompiler xpath = processor.newXPathCompiler();
        xpath.declareNamespace("cortex", "http://www.deutsche-digitale-bibliothek.de/cortex");
        xpath.declareNamespace("source", "http://www.deutsche-digitale-bibliothek.de/ns/cortex-item-source");
        xpath.declareNamespace("oai", "http://www.openarchives.org/OAI/2.0/");
        xpath.declareNamespace("mets", METS_NAMESPACE);
        cortexRecord = xpath.compile("/cortex:cortex");
        sourceRecord = xpath.compile("source:source/source:record");
        inlineMetadata = xpath.compile("*[1]");
        oaiMetadata = xpath.compile("/oai:record/oai:metadata/*[1]");
        metsRecord = xpath.compile("/mets:mets");
        providerInfo = xpath.compile("cortex:provider-info");

        final XsltCompiler compiler = processor.newXsltCompiler();
        cortexToIiif = compile(compiler, "cortex-to-iiif.xsl");
        xmlToJson = compile(compiler, "xml-to-json.xsl");
        metsmodsToIiif = compile(compiler, "metsmods-to-iiif.xsl");
    }

    private static XsltExecutable compile(XsltCompiler compiler, String name) throws IOException, SaxonApiException {
        final ClassPathResource resource = new ClassPathResource("xslt/" + name);
        try (InputStream input = resource.getInputStream()) {
            return compiler.compile(new StreamSource(input, resource.getURL().toExternalForm()));
        }
    }

    /**
     * Liefert das Manifest für ein DDB-Objekt. Bei Anfragen an Q1 oder Q2 trägt die
     * Manifest-ID die gewählte Testumgebung im Parameter {@code system}.
     *
     * @param request HTTP-Anfrage zur Ermittlung des Kontextpfads
     * @param id Base32-kodierte DDB-Objekt-ID
     * @param system optionale Testumgebung {@code Q1} oder {@code Q2}, andernfalls gilt Produktion
     * @return vollständiges UTF-8-Manifest oder JSON-Fehler mit passendem HTTP-Status
     */
    @GetMapping(path = "/{id:[^.]+}", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> getResource(HttpServletRequest request, @PathVariable String id,
                                         @RequestParam(required = false) String system) {
        if (!DDB_ID.matcher(id).matches()) {
            return error(HttpStatus.BAD_REQUEST, "Not a valid DDB ID");
        }

        final String itemId = id.toUpperCase(Locale.ROOT);
        final String host;
        final String key;
        final String query;
        switch (system == null ? "" : system.toUpperCase(Locale.ROOT)) {
            case "Q1" -> {
                host = "api-q1.deutsche-digitale-bibliothek.de";
                key = ddbApiKeyQ1;
                query = "?system=Q1";
            }
            case "Q2" -> {
                host = "api-q2.deutsche-digitale-bibliothek.de";
                key = ddbApiKeyQ2;
                query = "?system=Q2";
            }
            default -> {
                host = "api.deutsche-digitale-bibliothek.de";
                key = ddbApiKeyProd;
                query = "";
            }
        }
        final HttpUrl apiUrl = new HttpUrl.Builder()
                .scheme("https")
                .host(host)
                .addPathSegment("items")
                .addPathSegment(itemId)
                .build();
        final Request upstreamRequest = new Request.Builder()
                .url(apiUrl.newBuilder().addQueryParameter("oauth_consumer_key", key).build())
                .header("Accept", MediaType.APPLICATION_XML_VALUE)
                .build();
        final String manifestUrl = baseUrl + request.getContextPath() + "/" + itemId + query;

        final long start = System.nanoTime();
        try {
            final DocumentBuilder builder = processor.newDocumentBuilder();
            final XdmNode document;
            try (Response response = httpClient.newCall(upstreamRequest).execute()) {
                if (response.code() == HttpStatus.NOT_FOUND.value()) {
                    return error(HttpStatus.NOT_FOUND, "DDB item not found");
                }
                if (!response.isSuccessful()) {
                    LOG.warn("{}: DDB API responded with HTTP {}", itemId, response.code());
                    return error(HttpStatus.BAD_GATEWAY, "DDB API request failed");
                }
                final InputSource input = new InputSource(new MetadataInput(response.body().byteStream(), maxMetadataBytes));
                // Saxon erhält die Endpunkt-URL als Auflösungsbasis. Der API-Schlüssel verbleibt in der HTTP-Anfrage.
                input.setSystemId(apiUrl.toString());
                document = builder.build(CustomResolver.secureXmlSource(input));
            }
            final ManifestOutput manifest = new ManifestOutput(maxManifestBytes);
            transform(builder, document, itemId, manifestUrl, manifest);
            LOG.debug("{}: Manifest generated in {} ms", itemId, Duration.ofNanos(System.nanoTime() - start).toMillis());
            return ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON).contentLength(manifest.size())
                    .body(new InputStreamResource(manifest.getInputStream()));
        } catch (InterruptedIOException e) {
            return timeout(itemId);
        } catch (IOException e) {
            LOG.warn("{}: DDB API request failed", itemId, e);
            return error(HttpStatus.BAD_GATEWAY, "DDB API request failed");
        } catch (SaxonApiException | XPathException e) {
            if (NestedExceptionUtils.getMostSpecificCause(e) instanceof InterruptedIOException) {
                return timeout(itemId);
            }
            LOG.warn("{}: DDB metadata could not be transformed: {}", itemId, e.getMessage());
            return error(HttpStatus.BAD_GATEWAY, "DDB metadata could not be transformed");
        }
    }

    private void transform(DocumentBuilder builder, XdmNode document, String itemId, String manifestUrl, ManifestOutput output)
            throws SaxonApiException, XPathException {
        final XdmItem cortex = select(cortexRecord, document);
        if (cortex == null) {
            throw new SaxonApiException("DDB API did not return Cortex XML");
        }
        final XdmNode record = (XdmNode) select(sourceRecord, cortex);
        if (record != null && METS_NAMESPACE.equalsIgnoreCase(record.attribute("type"))) {
            // DDB liefert METS als eingebettetes XML oder als Text, optional innerhalb eines OAI-PMH-Datensatzes.
            final XdmNode inline = (XdmNode) select(inlineMetadata, record);
            final XdmNode metsDocument;
            if (inline == null) {
                final InputSource input = new InputSource(new StringReader(record.getStringValue().strip()));
                input.setSystemId(record.getBaseURI().toString());
                metsDocument = builder.build(CustomResolver.secureXmlSource(input));
            } else {
                metsDocument = builder.build(inline.asSource());
            }
            final XdmNode wrapped = (XdmNode) select(oaiMetadata, metsDocument);
            final XdmNode metadata = wrapped == null ? metsDocument : builder.build(wrapped.asSource());
            if (select(metsRecord, metadata) == null) {
                throw new SaxonApiException("Expected METS XML in DDB metadata");
            }
            final XsltTransformer transformer = transformer(metsmodsToIiif);
            transformer.setParameter(new QName("itemId"), new XdmAtomicValue(itemId));
            transformer.setParameter(new QName("itemUrl"), new XdmAtomicValue(manifestUrl));
            final XdmItem provider = select(providerInfo, cortex);
            if (provider != null) {
                transformer.setParameter(new QName("providerInfo"), provider);
            }
            transformer.setInitialContextNode(metadata);
            transformer.setDestination(processor.newSerializer(output));
            transformer.transform();
        } else {
            // Der Cortex-Pfad erzeugt zuerst die XML-Repräsentation für die Funktion xml-to-json().
            final XdmDestination intermediate = new XdmDestination();
            final XsltTransformer transformer = transformer(cortexToIiif);
            transformer.setParameter(new QName("uri"), new XdmAtomicValue(manifestUrl));
            transformer.setInitialContextNode(document);
            transformer.setDestination(intermediate);
            transformer.transform();

            final XsltTransformer serializer = xmlToJson.load();
            serializer.setInitialContextNode(intermediate.getXdmNode());
            serializer.setDestination(processor.newSerializer(output));
            serializer.transform();
        }
    }

    /** Bindet XML- und JSON-Abrufe an dasselbe Zeitbudget der Transformation. */
    private XsltTransformer transformer(XsltExecutable stylesheet) {
        final XsltTransformer transformer = stylesheet.load();
        final CustomResolver transformationResolver = resolver.forTransformation(Duration.ofMinutes(5));
        transformer.setResourceResolver(transformationResolver);
        transformer.setUnparsedTextResolver(transformationResolver);
        return transformer;
    }

    private static XdmItem select(XPathExecutable expression, XdmItem context) throws SaxonApiException {
        final XPathSelector selector = expression.load();
        selector.setContextItem(context);
        return selector.evaluateSingle();
    }

    private static ResponseEntity<Map<String, String>> error(HttpStatus status, String message) {
        return ResponseEntity.status(status).body(Map.of("error", message));
    }

    private static ResponseEntity<Map<String, String>> timeout(String itemId) {
        LOG.warn("{}: DDB API request timed out", itemId);
        return error(HttpStatus.GATEWAY_TIMEOUT, "DDB API request timed out");
    }

    /** Begrenzt die vom Parser gelesenen Bytes auch bei Antworten ohne HTTP-Längenangabe. */
    private static final class MetadataInput extends InputStream {

        private final InputStream source;
        private long remaining;

        private MetadataInput(InputStream source, int maxBytes) {
            this.source = source;
            remaining = maxBytes;
        }

        @Override
        public int read() throws IOException {
            final int value = source.read();
            if (value >= 0) {
                consume(1);
            }
            return value;
        }

        @Override
        public int read(byte[] bytes, int offset, int length) throws IOException {
            // Ein weiteres Byte unterscheidet eine Antwort am Limit von einer zu großen Antwort.
            final int count = source.read(bytes, offset, (int) Math.min(length, remaining + 1));
            if (count > 0) {
                consume(count);
            }
            return count;
        }

        private void consume(int count) throws IOException {
            remaining -= count;
            if (remaining < 0) {
                throw new IOException("DDB metadata exceeds the size limit");
            }
        }

        @Override
        public void close() throws IOException {
            source.close();
        }
    }

    /** Puffert das Manifest bis zum Byte-Limit, damit der HTTP-Status erst nach der Serialisierung feststeht. */
    private static final class ManifestOutput extends FastByteArrayOutputStream {

        private final int maxBytes;

        private ManifestOutput(int maxBytes) {
            this.maxBytes = maxBytes;
        }

        @Override
        public void write(int value) throws IOException {
            checkSize(1);
            super.write(value);
        }

        @Override
        public void write(byte[] bytes, int offset, int length) throws IOException {
            checkSize(length);
            super.write(bytes, offset, length);
        }

        private void checkSize(int bytesToWrite) throws IOException {
            if (bytesToWrite > maxBytes - size()) {
                throw new IOException("IIIF manifest exceeds the size limit");
            }
        }
    }
}
