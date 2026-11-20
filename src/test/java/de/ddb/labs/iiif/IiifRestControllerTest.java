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

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import okhttp3.HttpUrl;
import okhttp3.OkHttpClient;
import okhttp3.Protocol;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.ResponseBody;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import tools.jackson.databind.DeserializationFeature;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

class IiifRestControllerTest {

    private static final String CORTEX_ID = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
    private static final String METS_ID = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";
    private static final String MISSING_ID = "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC";
    private static final String UPSTREAM_FAILURE_ID = "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD";
    private static final String MALFORMED_XML_ID = "EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE";
    private static final String TIMEOUT_ID = "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF";
    private static final String BAD_METS_ID = "GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG";
    private static final String LARGE_METADATA_ID = "HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH";
    private static final String LARGE_MANIFEST_ID = "IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII";
    private static final int MAX_METADATA_BYTES = 8192;
    private static final int MAX_MANIFEST_BYTES = 4096;
    private static final JsonMapper JSON = JsonMapper.builder()
            .enable(DeserializationFeature.FAIL_ON_TRAILING_TOKENS)
            .build();

    private static final String CORTEX_XML = """
            <cortex xmlns="http://www.deutsche-digitale-bibliothek.de/cortex"
                    xmlns:item="http://www.deutsche-digitale-bibliothek.de/item"
                    xmlns:source="http://www.deutsche-digitale-bibliothek.de/ns/cortex-item-source"
                    xmlns:description="http://www.deutsche-digitale-bibliothek.de/ns/cortex-item-source-description">
                <properties><item-id>%s</item-id></properties>
                <view><item:item><item:title>Bibliothek Köln</item:title></item:item></view>
                <source:source><source:description>
                    <description:record ref="%s">
                        <description:id type="mets:div/@ID" value="page 2&amp;3"/>
                    </description:record>
                </source:description></source:source>
            </cortex>
            """.formatted(CORTEX_ID, METS_ID);

    private static final String METS_XML = """
            <mets:mets xmlns:mets="http://www.loc.gov/METS/" xmlns:xlink="http://www.w3.org/1999/xlink"
                       xmlns:mods="http://www.loc.gov/mods/v3">
                <mets:dmdSec ID="DMD"><mets:mdWrap MDTYPE="MODS"><mets:xmlData>
                    <mods:mods><mods:relatedItem><mods:titleInfo><mods:title>Zeitung</mods:title></mods:titleInfo></mods:relatedItem></mods:mods>
                </mets:xmlData></mets:mdWrap></mets:dmdSec>
                <mets:amdSec ID="AMD"/>
                <mets:fileSec><mets:fileGrp USE="DEFAULT">
                    <mets:file ID="IMAGE" MIMETYPE="image/jpeg">
                        <mets:FLocat xlink:href="https://images.example.org/page.jpg" LOCTYPE="URL"/>
                    </mets:file>
                </mets:fileGrp></mets:fileSec>
                <mets:structMap TYPE="PHYSICAL"><mets:div TYPE="physSequence">
                    <mets:div ID="P1" TYPE="page" ORDER="1"><mets:fptr FILEID="IMAGE"/></mets:div>
                </mets:div></mets:structMap>
            </mets:mets>
            """;

    private static MockMvc mvc;

    @BeforeAll
    static void setUp() throws Exception {
        final OkHttpClient httpClient = new OkHttpClient.Builder()
                .addInterceptor(chain -> upstreamResponse(chain.request()))
                .build();
        mvc = MockMvcBuilders.standaloneSetup(
                new IiifRestController("https://iiif.example.org/", MAX_METADATA_BYTES, MAX_MANIFEST_BYTES, httpClient))
                .defaultResponseCharacterEncoding(StandardCharsets.UTF_8)
                .build();
    }

    @Test
    void rejectsInvalidIdBeforeCallingDdb() throws Exception {
        final JsonNode error = readJson(mvc.perform(get("/" + "0".repeat(32)))
                .andExpect(status().isBadRequest()));
        assertEquals("Not a valid DDB ID", error.path("error").stringValue());
    }

    @Test
    void returnsCortexJsonWithCanonicalEnvironmentAndContextPath() throws Exception {
        final JsonNode manifest = readJson(mvc.perform(get("/presentation/" + "a".repeat(32) + "?system=q1&other=ignored")
                        .contextPath("/presentation"))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON)));
        assertEquals("Manifest", manifest.path("type").stringValue());
        assertEquals("https://iiif.example.org/presentation/" + CORTEX_ID + "?system=Q1", manifest.path("id").stringValue());
        assertEquals("Bibliothek Köln", manifest.at("/label/de/0").stringValue());
        assertEquals("https://api-q1.deutsche-digitale-bibliothek.de/2/items/" + CORTEX_ID,
                manifest.at("/seeAlso/0/id").stringValue());
        final HttpUrl viewer = HttpUrl.get(manifest.at("/rendering/0/id").stringValue());
        assertEquals("https://api-q1.deutsche-digitale-bibliothek.de/2/items/" + METS_ID + "/source/record",
                viewer.queryParameter("tx_dlf[id]"));
        assertEquals("page 2&3", viewer.queryParameter("tx_dlf[page]"));
    }

    @Test
    void transformsInlineOaiWrappedMetsWithNoProvider() throws Exception {
        final JsonNode manifest = readJson(mvc.perform(get("/" + METS_ID + "?system=Q2"))
                .andExpect(status().isOk()));
        assertEquals("Manifest", manifest.path("type").stringValue());
        assertEquals("Zeitung", manifest.at("/label/de/0").stringValue());
        assertTrue(manifest.path("provider").isMissingNode());
        assertEquals("https://iiif.example.org/" + METS_ID + "/canvas/P1?system=Q2", manifest.at("/items/0/id").stringValue());
        assertEquals("https://images.example.org/page.jpg", manifest.at("/items/0/items/0/items/0/body/id").stringValue());
        assertEquals("https://api-q2.deutsche-digitale-bibliothek.de/2/items/" + METS_ID,
                manifest.at("/seeAlso/0/id").stringValue());
    }

    @Test
    void mapsUpstreamStatusesToJsonErrors() throws Exception {
        final JsonNode missing = readJson(mvc.perform(get("/" + MISSING_ID))
                .andExpect(status().isNotFound()));
        assertEquals("DDB item not found", missing.path("error").stringValue());

        final JsonNode upstreamFailure = readJson(mvc.perform(get("/" + UPSTREAM_FAILURE_ID))
                .andExpect(status().isBadGateway()));
        assertEquals("DDB API request failed", upstreamFailure.path("error").stringValue());

        final JsonNode timeout = readJson(mvc.perform(get("/" + TIMEOUT_ID))
                .andExpect(status().isGatewayTimeout()));
        assertEquals("DDB API request timed out", timeout.path("error").stringValue());
    }

    @Test
    void returnsOneJsonErrorWhenUpstreamXmlIsMalformed() throws Exception {
        final JsonNode error = readJson(mvc.perform(get("/" + MALFORMED_XML_ID))
                .andExpect(status().isBadGateway()));
        assertEquals(JSON.createObjectNode().put("error", "DDB metadata could not be transformed"), error);
    }

    @Test
    void rejectsNonMetsDocumentMarkedAsMets() throws Exception {
        final JsonNode error = readJson(mvc.perform(get("/" + BAD_METS_ID))
                .andExpect(status().isBadGateway()));
        assertEquals("DDB metadata could not be transformed", error.path("error").stringValue());
    }

    @Test
    void capsBothUpstreamMetadataAndCompleteManifest() throws Exception {
        final JsonNode oversizedMetadata = readJson(mvc.perform(get("/" + LARGE_METADATA_ID))
                .andExpect(status().isBadGateway()));
        assertTrue(oversizedMetadata.path("error").isString());

        final JsonNode oversizedManifest = readJson(mvc.perform(get("/" + LARGE_MANIFEST_ID))
                .andExpect(status().isBadGateway()));
        assertEquals("DDB metadata could not be transformed", oversizedManifest.path("error").stringValue());
    }

    private static JsonNode readJson(ResultActions response) {
        return JSON.readTree(response.andReturn().getResponse().getContentAsByteArray());
    }

    private static Response upstreamResponse(Request request) throws SocketTimeoutException {
        assertNull(request.url().query());
        assertNull(request.header("Authorization"));
        assertEquals(MediaType.APPLICATION_XML_VALUE, request.header("Accept"));
        final Response.Builder response = new Response.Builder()
                .request(request).protocol(Protocol.HTTP_1_1).code(200).message("test response");
        final String body;
        switch (request.url().encodedPath()) {
            case "/2/items/" + CORTEX_ID -> {
                assertEquals("api-q1.deutsche-digitale-bibliothek.de", request.url().host());
                body = CORTEX_XML;
            }
            case "/2/items/" + METS_ID -> {
                assertEquals("api-q2.deutsche-digitale-bibliothek.de", request.url().host());
                body = wrapMets(METS_XML);
            }
            case "/2/items/" + MISSING_ID -> {
                assertEquals("api.deutsche-digitale-bibliothek.de", request.url().host());
                response.code(404);
                body = "missing";
            }
            case "/2/items/" + UPSTREAM_FAILURE_ID -> {
                response.code(403);
                body = "upstream sensitive detail";
            }
            case "/2/items/" + MALFORMED_XML_ID -> body = "<invalid>";
            case "/2/items/" + TIMEOUT_ID -> throw new SocketTimeoutException("test timeout");
            case "/2/items/" + BAD_METS_ID -> body = wrapMets("<not-mets/>");
            case "/2/items/" + LARGE_METADATA_ID -> body = CORTEX_XML + " ".repeat(MAX_METADATA_BYTES);
            case "/2/items/" + LARGE_MANIFEST_ID -> body = CORTEX_XML.replace("Bibliothek Köln", "Z".repeat(MAX_MANIFEST_BYTES));
            default -> throw new AssertionError("Unexpected request to " + request.url().encodedPath());
        }
        return response.body(ResponseBody.create(body, okhttp3.MediaType.get("application/xml"))).build();
    }

    private static String wrapMets(String mets) {
        return """
                <cortex xmlns="http://www.deutsche-digitale-bibliothek.de/cortex"
                        xmlns:source="http://www.deutsche-digitale-bibliothek.de/ns/cortex-item-source"
                        xmlns:oai="http://www.openarchives.org/OAI/2.0/">
                    <source:source><source:record type="http://www.loc.gov/METS/">
                        <oai:record><oai:metadata>%s</oai:metadata></oai:record>
                    </source:record></source:source>
                </cortex>
                """.formatted(mets);
    }
}
