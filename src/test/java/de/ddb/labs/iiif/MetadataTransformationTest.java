/*
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

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;

import java.io.InputStream;
import java.io.StringReader;
import java.io.StringWriter;
import java.net.InetAddress;
import java.time.Duration;
import javax.xml.transform.stream.StreamSource;
import net.sf.saxon.lib.ResourceRequest;
import net.sf.saxon.s9api.Processor;
import net.sf.saxon.s9api.QName;
import net.sf.saxon.s9api.SaxonApiException;
import net.sf.saxon.s9api.XdmAtomicValue;
import net.sf.saxon.s9api.XdmDestination;
import net.sf.saxon.s9api.XsltTransformer;
import net.sf.saxon.trans.XPathException;
import okhttp3.Interceptor;
import okhttp3.OkHttpClient;
import okhttp3.Protocol;
import okhttp3.Response;
import okhttp3.ResponseBody;
import org.junit.jupiter.api.Test;
import org.xml.sax.InputSource;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

class MetadataTransformationTest {

    private static final String MANIFEST_URL = "https://iiif.example.org/item?system=Q1";
    private static final String IMAGE_BASE = "https://images.example.org/iiif/image";
    private static final String METS_XML = """
            <mets:mets xmlns:mets="http://www.loc.gov/METS/"
                       xmlns:mods="http://www.loc.gov/mods/v3"
                       xmlns:xlink="http://www.w3.org/1999/xlink">
                <mets:dmdSec><mets:mdWrap><mets:xmlData>
                    <mods:mods><mods:relatedItem><mods:titleInfo><mods:title>Zeitschrift</mods:title></mods:titleInfo></mods:relatedItem></mods:mods>
                </mets:xmlData></mets:mdWrap></mets:dmdSec>
                <mets:fileSec><mets:fileGrp USE="IMAGE">
                    <mets:file ID="I1" MIMETYPE="application/vnd.kitodo.iiif">
                        <mets:FLocat xlink:href="%s/full/max/0/default.jpg?view=public"/>
                    </mets:file>
                </mets:fileGrp></mets:fileSec>
                <mets:structMap TYPE="PHYSICAL"><mets:div>
                    <mets:div ID="P1" TYPE="page"><mets:fptr FILEID="I1"/></mets:div>
                </mets:div></mets:structMap>
            </mets:mets>
            """.formatted(IMAGE_BASE);

    @Test
    void cortexReferencesOnlyGeneratedCanvasesAndHandlesUnavailableEnrichment() throws Exception {
        final String metadata = """
                <cortex xmlns="http://www.deutsche-digitale-bibliothek.de/cortex"
                        xmlns:item="http://www.deutsche-digitale-bibliothek.de/item">
                    <provider-info><provider-ddb-id>PROVIDER</provider-ddb-id><provider-name>Bibliothek</provider-name></provider-info>
                    <view><item:item><item:title>Ausgabe</item:title>
                        <item:fields usage="display"><item:field><item:name>Quelle</item:name>
                            <item:value>https://example.org/?a=1&amp;b=2</item:value>
                        </item:field></item:fields>
                    </item:item></view>
                    <binaries>
                        <binary mimetype="image/gif" ref="unsupported"/>
                        <binary mimetype="image/jpeg" primary="true" ref="missing"/>
                        <binary mimetype="application/pdf" ref="document"/>
                    </binaries>
                </cortex>
                """;
        final JsonNode result = transform(metadata, "cortex-to-iiif", "uri", chain -> response(chain, 404, ""));
        final String canvasId = "https://iiif.example.org/item/canvas/p2?system=Q1";

        assertEquals(MANIFEST_URL, result.path("id").asString());
        assertEquals(1, result.path("items").size());
        assertEquals(canvasId, result.at("/items/0/id").asString());
        assertEquals(canvasId, result.at("/items/0/items/0/items/0/target").asString());
        assertEquals(canvasId, result.at("/start/id").asString());
        assertEquals(1, result.at("/structures/0/items").size());
        assertEquals(canvasId, result.at("/structures/0/items/0/items/0/id").asString());
        assertEquals("Bibliothek", result.at("/provider/0/label/none/0").asString());
        assertFalse(result.at("/provider/0").has("logo"));
        assertTrue(result.at("/metadata/0/value/none/0").asString().contains("a=1&amp;b=2"));
    }

    @Test
    void cortexUsesAnImageForThePrimaryVideoThumbnailAndMp3ForAudio() throws Exception {
        final String metadata = """
                <cortex xmlns="http://www.deutsche-digitale-bibliothek.de/cortex">
                    <binaries>
                        <binary mimetype="video/mp4" primary="true" position="1" ref="video"/>
                        <binary mimetype="image/jpeg" position="1" ref="preview"/>
                        <binary mimetype="audio/mpeg" position="2" ref="sound"/>
                    </binaries>
                </cortex>
                """;
        final JsonNode result = transform(metadata, "cortex-to-iiif", "uri", chain -> response(chain, 200, """
                {"width":320,"height":240}
                """));

        assertEquals("https://iiif.deutsche-digitale-bibliothek.de/image/2/preview/full/200,/0/default.jpg",
                result.at("/thumbnail/0/id").asString());
        final JsonNode audio = result.at("/items/2/items/0/items/0/body");
        assertEquals("https://api.deutsche-digitale-bibliothek.de/binary/sound.mp3", audio.path("id").asString());
        assertEquals("audio/mpeg", audio.path("format").asString());
    }

    @Test
    void metsUsesImageApi3WithScalarProfileAndContextArray() throws Exception {
        final JsonNode result = transform(METS_XML, "metsmods-to-iiif", "itemUrl", chain -> {
            assertEquals(IMAGE_BASE + "/info.json?view=public", chain.request().url().toString());
            return response(chain, 200, """
                    {"@context":["https://example.org/context.json","http://iiif.io/api/image/3/context.json"],
                     "profile":"level2","width":120,"height":90}
                    """);
        });

        assertEquals("https://iiif.example.org/item/canvas/P1?system=Q1", result.at("/start/id").asString());
        assertEquals(120, result.at("/items/0/width").asInt());
        assertEquals(90, result.at("/items/0/height").asInt());
        assertEquals("1", result.at("/items/0/label/none/0").asString());
        final JsonNode body = result.at("/items/0/items/0/items/0/body");
        assertEquals(IMAGE_BASE + "/full/max/0/default.jpg?view=public", body.path("id").asString());
        assertEquals("ImageService3", body.at("/service/0/type").asString());
        assertEquals("level2", body.at("/service/0/profile").asString());
        assertEquals(IMAGE_BASE + "/full/120,90/0/default.jpg?view=public", result.at("/thumbnail/0/id").asString());
    }

    @Test
    void metsKeepsOriginalImageWhenItsInfoIsUnavailable() throws Exception {
        final JsonNode result = transform(METS_XML, "metsmods-to-iiif", "itemUrl", chain -> response(chain, 503, ""));

        assertEquals(1, result.path("items").size());
        final JsonNode body = result.at("/items/0/items/0/items/0/body");
        assertEquals(IMAGE_BASE + "/full/max/0/default.jpg?view=public", body.path("id").asString());
        assertFalse(body.has("service"));
    }

    @Test
    void xmlParserSupportsNamespacesAndRejectsDoctypes() throws Exception {
        final Processor processor = new Processor(false);
        final String xml = "<data xmlns=\"urn:example:data\">Bibliothek</data>";
        assertEquals("Bibliothek", processor.newDocumentBuilder().build(
                CustomResolver.secureXmlSource(new InputSource(new StringReader(xml)))).getStringValue());
        assertThrows(SaxonApiException.class, () -> processor.newDocumentBuilder().build(CustomResolver.secureXmlSource(
                new InputSource(new StringReader("<!DOCTYPE data [<!ELEMENT data (#PCDATA)>]>" + xml)))));
    }

    @Test
    void remoteMetadataAddressesAreRestrictedToPublicUnicast() {
        assertFalse(CustomResolver.isPublicAddress(InetAddress.ofLiteral("127.0.0.1")));
        assertFalse(CustomResolver.isPublicAddress(InetAddress.ofLiteral("10.0.0.1")));
        assertFalse(CustomResolver.isPublicAddress(InetAddress.ofLiteral("100.64.0.1")));
        assertFalse(CustomResolver.isPublicAddress(InetAddress.ofLiteral("::1")));
        assertFalse(CustomResolver.isPublicAddress(InetAddress.ofLiteral("fd00::1")));
        assertTrue(CustomResolver.isPublicAddress(InetAddress.ofLiteral("1.1.1.1")));
        assertTrue(CustomResolver.isPublicAddress(InetAddress.ofLiteral("2606:4700:4700::1111")));
    }

    @Test
    void expiredEnrichmentBudgetSkipsExternalRequests() {
        final OkHttpClient client = new OkHttpClient.Builder()
                .addInterceptor(chain -> fail("No request should run after the time budget expires"))
                .build();
        final CustomResolver resolver = new CustomResolver(client).forTransformation(Duration.ZERO);
        final ResourceRequest request = new ResourceRequest();
        request.uri = "https://example.org/document.xml";
        assertThrows(XPathException.class, () -> resolver.resolve(request));
    }

    private static JsonNode transform(String metadata, String stylesheet, String idParameter, Interceptor upstream) throws Exception {
        final Processor processor = new Processor(false);
        final XsltTransformer transformer = loadStylesheet(processor, stylesheet);
        final CustomResolver resolver = new CustomResolver(new OkHttpClient.Builder().addInterceptor(upstream).build());
        transformer.setResourceResolver(resolver);
        transformer.setUnparsedTextResolver(resolver);
        transformer.setParameter(new QName(idParameter), new XdmAtomicValue(MANIFEST_URL));
        transformer.setInitialContextNode(processor.newDocumentBuilder().build(
                CustomResolver.secureXmlSource(new InputSource(new StringReader(metadata)))));
        final StringWriter output = new StringWriter();
        if (stylesheet.equals("cortex-to-iiif")) {
            final XdmDestination intermediate = new XdmDestination();
            transformer.setDestination(intermediate);
            transformer.transform();
            final XsltTransformer serializer = loadStylesheet(processor, "xml-to-json");
            serializer.setInitialContextNode(intermediate.getXdmNode());
            serializer.setDestination(processor.newSerializer(output));
            serializer.transform();
        } else {
            transformer.setDestination(processor.newSerializer(output));
            transformer.transform();
        }
        return new ObjectMapper().readTree(output.toString());
    }

    private static XsltTransformer loadStylesheet(Processor processor, String stylesheet) throws Exception {
        try (InputStream source = MetadataTransformationTest.class.getResourceAsStream("/xslt/" + stylesheet + ".xsl")) {
            return processor.newXsltCompiler().compile(new StreamSource(source)).load();
        }
    }

    private static Response response(Interceptor.Chain chain, int status, String body) {
        return new Response.Builder()
                .request(chain.request())
                .protocol(Protocol.HTTP_1_1)
                .code(status)
                .message("Synthetic upstream response")
                .body(ResponseBody.create(body, null))
                .build();
    }
}
