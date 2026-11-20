<?xml version="1.0" encoding="UTF-8"?>
<!-- 
Copyright 2023-2026 Michael Büchner, Deutsche Digitale Bibliothek

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-->
<xsl:stylesheet exclude-result-prefixes="cortex ddblabs j ns3 ns4 source ns5 xs" version="3.0" xmlns="http://www.w3.org/2005/xpath-functions" xmlns:cortex="http://www.deutsche-digitale-bibliothek.de/cortex" xmlns:ddblabs="https://labs.deutsche-digitale-bibliothek.de" xmlns:j="http://www.w3.org/2005/xpath-functions" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:ns3="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:ns4="http://www.deutsche-digitale-bibliothek.de/item" xmlns:ns5="http://www.deutsche-digitale-bibliothek.de/ns/cortex-item-source-description" xmlns:source="http://www.deutsche-digitale-bibliothek.de/ns/cortex-item-source" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <!--
        Erzeugt ein Manifest nach IIIF Presentation API 3.0 aus einem Cortex-Datensatz.
        Die Cortex-Ansicht liefert Titel und Metadaten, die Binärreferenzen liefern die
        Reihenfolge und Inhalte der Canvases. Das Ergebnis entspricht der standardisierten
        XML-Darstellung für JSON. xml-to-json.xsl serialisiert diese Zwischenstruktur.
    -->
    <xsl:output encoding="UTF-8" method="xml" />

    <!--
        Der Controller übergibt die öffentliche Manifest-URL und die API-Basis des gewählten DDB-Systems.
        Die Standardwerte dienen eigenständigen Testläufen.
    -->
    <xsl:param name="uri">https://labs.deutsche-digitale-bibliothek.de/iiif/presentation/3/ABCDEFGHIJKLMNOPQRSTUVWXYZ012345</xsl:param>
    <xsl:param name="ddbApiBase" as="xs:string" select="'https://api.deutsche-digitale-bibliothek.de/2/'" />

    <!-- Der öffentliche DDB-Binärdienst liefert Medien unabhängig von der Metadaten-API. -->
    <xsl:variable name="ddbBinaryBase" as="xs:string" select="'https://iiif.deutsche-digitale-bibliothek.de/binary/'" />

    <!--
        Canvases, Annotationen und Ranges übernehmen die Umgebung des Manifests.
        Ihr Pfad steht vor der Query, zum Beispiel /canvas/p1?system=Q1.
    -->
    <xsl:function name="ddblabs:resource-id" as="xs:string">
        <xsl:param name="path" as="xs:string" />
        <xsl:sequence select="
                if (contains($uri, '?'))
                then substring-before($uri, '?') || $path || '?' || substring-after($uri, '?')
                else $uri || $path" />
    </xsl:function>

    <!--
        IIIF-Metadaten und Zuschreibungen können HTML enthalten. Nur HTTP(S)-Ziele
        werden verlinkt. Der HTML-Serializer kodiert den Anzeigetext und Attributwerte.
    -->
    <xsl:function name="ddblabs:link-text" as="xs:string">
        <xsl:param name="label" as="xs:string" />
        <xsl:param name="url" as="xs:string?" />
        <xsl:variable name="value" as="node()*">
            <xsl:choose>
                <xsl:when test="matches(normalize-space($url), '^https?://[^/\s]', 'i')">
                    <a xmlns="" href="{normalize-space($url)}" target="_blank" rel="noopener noreferrer"><xsl:value-of select="$label" /></a>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:value-of select="$label" />
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        <xsl:sequence select="serialize($value, map {'method': 'html'})" />
    </xsl:function>

    <!-- Manifest und Cortex-Metadaten -->

    <xsl:template match="/">
        <xsl:variable name="id">
            <xsl:value-of select="/cortex:cortex/cortex:properties/cortex:item-id" />
        </xsl:variable>
        <xsl:variable name="provider" select="/cortex:cortex/cortex:provider-info[1]" />
        <xsl:variable name="providerId" select="normalize-space($provider/cortex:provider-ddb-id[1])" />
        <xsl:variable name="providerName" select="normalize-space($provider/cortex:provider-name[1])" />

        <!--
            Die primäre Binärreferenz aus dem separaten Cortex-Datensatz der Einrichtung dient als Logo.
            Falls der Datensatz oder das Bild fehlt, bleibt die übrige Anbieterangabe erhalten.
        -->
        <xsl:variable name="providerLogo" as="xs:string?">
            <xsl:if test="$providerId and $providerName">
                <xsl:try>
                    <xsl:variable name="providerUrl" select="$ddbApiBase || 'items/' || encode-for-uri($providerId)" />
                    <xsl:sequence select="(doc($providerUrl)/cortex:cortex/cortex:binaries/cortex:binary[@primary = 'true']/@ref)[1] ! string(.)" />
                    <xsl:catch />
                </xsl:try>
            </xsl:if>
        </xsl:variable>

        <!--
            Die Position unter den unterstützten Binärdateien bestimmt die IDs.
            Canvases werden einmal erzeugt. Startverweis und Ranges verwenden anschließend
            die IDs der tatsächlich erzeugten Canvases, auch wenn ein Bild ausfällt.
        -->
        <xsl:variable name="binaries" select="/cortex:cortex/cortex:binaries/cortex:binary[@mimetype = ('image/jpeg', 'application/pdf', 'video/mp4', 'audio/mpeg')]" />
        <xsl:variable name="canvases" as="element(j:map)*">
            <xsl:apply-templates select="$binaries" />
        </xsl:variable>
        <xsl:variable name="canvasIds" select="$canvases/j:string[@key = 'id']/string()" />
        <xsl:variable name="primaryCanvasId" select="ddblabs:resource-id('/canvas/p' || index-of($binaries ! string(@primary), 'true')[1])" />

        <map>
            <string key="@context">http://iiif.io/api/presentation/3/context.json</string>
            <string key="id">
                <xsl:value-of select="$uri" />
            </string>
            <string key="type">Manifest</string>
            <map key="label">
                <array key="de">
                    <string>
                        <xsl:value-of select="/cortex:cortex/cortex:view/ns4:item/ns4:title" />
                    </string>
                </array>
            </map>
            <!-- Anzeigefelder übernehmen ihre Cortex-Beschriftung und verwenden vorhandene RDF-Links. -->
            <array key="metadata">
                <xsl:for-each select="/cortex:cortex/cortex:view/ns4:item/ns4:fields[@usage = 'display']/ns4:field">
                    <map>
                        <map key="label">
                            <array key="de">
                                <string>
                                    <xsl:value-of select="ns4:name" />
                                </string>
                            </array>
                        </map>
                        <map key="value">
                            <array key="none">
                                <xsl:for-each select="ns4:value">
                                    <string>
                                        <xsl:value-of select="ddblabs:link-text(string(.), string((@ns3:resource, .)[1]))" />
                                    </string>
                                </xsl:for-each>
                            </array>
                        </map>
                    </map>
                </xsl:for-each>
            </array>
            <!-- Lieferungen aus Museum und Film verwenden eigene Feld-IDs für die Zusammenfassung. -->
            <xsl:if test="/cortex:cortex/cortex:view/ns4:item/ns4:fields[@usage = 'display']/ns4:field[@id = 'flex_mus_neu_050' or @id = 'flex_film_007']">
                <map key="summary">
                    <array key="de">
                        <xsl:for-each select="/cortex:cortex/cortex:view/ns4:item/ns4:fields[@usage = 'display']/ns4:field[@id = 'flex_mus_neu_050' or @id = 'flex_film_007']/ns4:value">
                            <string>
                                <xsl:value-of select="." />
                            </string>
                        </xsl:for-each>
                    </array>
                </map>
            </xsl:if>
            <!-- Das primäre JPEG oder ein JPEG mit derselben Cortex-Position dient als Manifestvorschau. -->
            <xsl:variable name="primaryBinary" select="$binaries[@primary = 'true'][1]" />
            <xsl:variable name="thumbId" select="(
                    $primaryBinary[@mimetype = 'image/jpeg']/@ref,
                    $binaries[@mimetype = 'image/jpeg'][@position = $primaryBinary/@position]/@ref
                    )[normalize-space(.)][1]" />
            <xsl:if test="$thumbId">
                <array key="thumbnail">
                    <map>
                        <string key="id">
                            <xsl:text>https://iiif.deutsche-digitale-bibliothek.de/image/2/</xsl:text>
                            <xsl:value-of select="$thumbId" />
                            <xsl:text>/full/200,/0/default.jpg</xsl:text>
                        </string>
                        <string key="type">Image</string>
                        <string key="format">image/jpeg</string>
                        <array key="service">
                            <map>
                                <string key="id">
                                    <xsl:text>https://iiif.deutsche-digitale-bibliothek.de/image/2/</xsl:text>
                                    <xsl:value-of select="$thumbId" />
                                </string>
                                <string key="type">ImageService2</string>
                                <string key="profile">level2</string>
                            </map>
                        </array>
                    </map>
                </array>
            </xsl:if>
            <string key="viewingDirection">left-to-right</string>
            <array key="behavior">
                <string>individuals</string>
            </array>
            <!-- Die Lizenzreferenz stammt aus dem RDF-Attribut der Cortex-Ansicht. -->
            <string key="rights">
                <xsl:value-of select="/cortex:cortex/cortex:view/ns4:item/ns4:license/@ns3:resource" />
            </string>
            <!-- Die Zuschreibung verlinkt den Namen der Institution möglichst mit der Herkunfts-URL. -->
            <map key="requiredStatement">
                <map key="label">
                    <array key="en">
                        <string>Attribution</string>
                    </array>
                    <array key="de">
                        <string>Zuschreibung</string>
                    </array>
                </map>
                <map key="value">
                    <array key="none">
                        <string>
                            <xsl:value-of select="ddblabs:link-text(
                                    string((/cortex:cortex/cortex:view/ns4:item/ns4:institution/ns4:name)[1]),
                                    (cortex:cortex/cortex:view/ns4:item/ns4:origin, $provider/cortex:provider-uri)[normalize-space(.)][1])" />
                        </string>
                    </array>
                </map>
            </map>
            <!-- Die DDB-Organisation wird zum IIIF-Agent, sobald ID und Name vorliegen. -->
            <xsl:if test="$providerId and $providerName">
                <array key="provider">
                    <map>
                        <string key="id">
                            <xsl:text>https://www.deutsche-digitale-bibliothek.de/organization/</xsl:text>
                            <xsl:value-of select="$providerId" />
                        </string>
                        <string key="type">Agent</string>
                        <map key="label">
                            <array key="none">
                                <string>
                                    <xsl:value-of select="$providerName" />
                                </string>
                            </array>
                        </map>
                        <array key="seeAlso">
                            <map>
                                <string key="id">
                                    <xsl:text>https://www.deutsche-digitale-bibliothek.de/organization/</xsl:text>
                                    <xsl:value-of select="$providerId" />
                                </string>
                                <string key="type">Text</string>
                                <map key="label">
                                    <array key="de">
                                        <string>
                                            <xsl:value-of select="$providerName" />
                                            <xsl:text> bei der Deutschen Digitalen Bibliothek</xsl:text>
                                        </string>
                                    </array>
                                </map>
                                <string key="format">text/html</string>
                            </map>
                        </array>
                        <xsl:if test="$providerLogo">
                            <array key="logo">
                                <map>
                                    <string key="id">
                                        <xsl:text>https://iiif.deutsche-digitale-bibliothek.de/image/2/</xsl:text>
                                        <xsl:value-of select="$providerLogo" />
                                        <xsl:text>/full/full/0/default.jpg</xsl:text>
                                    </string>
                                    <string key="type">Image</string>
                                    <string key="format">image/jpeg</string>
                                    <array key="service">
                                        <map>
                                            <string key="id">
                                                <xsl:text>https://iiif.deutsche-digitale-bibliothek.de/image/2/</xsl:text>
                                                <xsl:value-of select="$providerLogo" />
                                            </string>
                                            <string key="type">ImageService2</string>
                                            <string key="profile">level2</string>
                                        </map>
                                    </array>
                                </map>
                            </array>
                        </xsl:if>
                        <xsl:if test="/cortex:cortex/cortex:provider-info/cortex:provider-uri">
                            <array key="homepage">
                                <map>
                                    <string key="id">
                                        <xsl:value-of select="/cortex:cortex/cortex:provider-info/cortex:provider-uri" />
                                    </string>
                                    <string key="type">Text</string>
                                    <map key="label">
                                        <array key="none">
                                            <string>
                                                <xsl:value-of select="$providerName" />
                                            </string>
                                        </array>
                                    </map>
                                    <string key="format">text/html</string>
                                </map>
                            </array>
                        </xsl:if>
                    </map>
                </array>
            </xsl:if>
            <!-- Die DDB-Objektseite führt zur öffentlichen Ansicht des Datensatzes. -->
            <array key="homepage">
                <map>
                    <string key="id">
                        <xsl:text>https://www.deutsche-digitale-bibliothek.de/item/</xsl:text>
                        <xsl:value-of select="$id" />
                    </string>
                    <string key="type">Text</string>
                    <map key="label">
                        <array key="none">
                            <string>Deutsche Digitale Bibliothek</string>
                        </array>
                    </map>
                    <string key="format">text/html</string>
                </map>
            </array>
            <!--
                Das Logo beim Agent ist die reguläre Anbieterangabe nach IIIF Presentation 3.
                Die zusätzliche Angabe auf Manifestebene erhält die Logoanzeige in Mirador 3.
            -->
            <xsl:if test="$providerLogo">
                <array key="logo">
                    <map>
                        <string key="id">
                            <xsl:text>https://iiif.deutsche-digitale-bibliothek.de/image/2/</xsl:text>
                            <xsl:value-of select="$providerLogo" />
                            <xsl:text>/full/full/0/default.jpg</xsl:text>
                        </string>
                        <string key="type">Image</string>
                        <string key="format">image/jpeg</string>
                        <array key="service">
                            <map>
                                <string key="id">
                                    <xsl:text>https://iiif.deutsche-digitale-bibliothek.de/image/2/</xsl:text>
                                    <xsl:value-of select="$providerLogo" />
                                </string>
                                <string key="type">ImageService2</string>
                                <string key="profile">level2</string>
                            </map>
                        </array>
                    </map>
                </array>
            </xsl:if>
            <!-- seeAlso verweist auf die maschinenlesbaren Cortex-Metadaten. -->
            <array key="seeAlso">
                <map>
                    <string key="id">
                        <xsl:value-of select="$ddbApiBase || 'items/' || $id" />
                    </string>
                    <string key="type">Dataset</string>
                    <string key="format">application/xml</string>
                    <string key="profile">https://www.deutsche-digitale-bibliothek.de/ns/cortex</string>
                </map>
            </array>
            <!--
                rendering sammelt alternative Ansichten zum Manifest. PDF-Dateien und
                Vimeo-Videos kommen aus den Binärreferenzen. Liegt die Seiten-ID einer
                METS-Struktureinheit vor, führt sie im DFG-Viewer zur bezeichneten Seite.
            -->
            <xsl:variable name="metsSourceRecord" select="(
                    /cortex:cortex/source:source/source:description/ns5:record[ns5:id[@type = 'mets:div/@ID']/@value]
                )[1]" />
            <xsl:if test="/cortex:cortex/cortex:binaries/cortex:binary[@mimetype = 'application/pdf'] or /cortex:cortex/cortex:binaries/cortex:binary[@mimetype = 'video/vnd.ddbkultur.vimeo'] or $metsSourceRecord">
                <array key="rendering">
                    <xsl:if test="/cortex:cortex/cortex:binaries/cortex:binary[@mimetype = 'application/pdf']">
                        <xsl:for-each select="/cortex:cortex/cortex:binaries/cortex:binary[@mimetype = 'application/pdf']">
                            <map>
                                <string key="id">
                                    <xsl:value-of select="$ddbBinaryBase || @ref || '.pdf'" />
                                </string>
                                <string key="type">Text</string>
                                <map key="label">
                                    <array key="de">
                                        <string>PDF-Ansicht</string>
                                    </array>
                                </map>
                                <string key="format">application/pdf</string>
                            </map>
                        </xsl:for-each>
                    </xsl:if>
                    <xsl:if test="/cortex:cortex/cortex:binaries/cortex:binary[@mimetype = 'video/vnd.ddbkultur.vimeo']">
                        <xsl:for-each select="/cortex:cortex/cortex:binaries/cortex:binary[@mimetype = 'video/vnd.ddbkultur.vimeo']">
                            <map>
                                <string key="id">
                                    <xsl:text>https://vimeo.com/</xsl:text>
                                    <xsl:value-of select="@ref" />
                                </string>
                                <string key="type">Video</string>
                                <map key="label">
                                    <array key="de">
                                        <string>Vimeo-Video</string>
                                    </array>
                                </map>
                                <string key="format">video/vnd.ddbkultur.vimeo</string>
                            </map>
                        </xsl:for-each>
                    </xsl:if>
                    <xsl:if test="$metsSourceRecord">
                        <xsl:variable name="metsSourceUrl" select="
                                $ddbApiBase || 'items/' || encode-for-uri(string($metsSourceRecord/@ref)) || '/source/record'
                            " />
                        <xsl:variable name="metsPage" select="string(($metsSourceRecord/ns5:id[@type = 'mets:div/@ID']/@value)[1])" />
                        <map>
                            <string key="id">
                                <xsl:text>https://viewer.deutsche-digitale-bibliothek.de/index.php?id=1&amp;tx_dlf[id]=</xsl:text>
                                <xsl:value-of select="encode-for-uri($metsSourceUrl)" />
                                <xsl:text>&amp;tx_dlf[page]=</xsl:text>
                                <xsl:value-of select="encode-for-uri($metsPage)" />
                            </string>
                            <string key="type">Text</string>
                            <map key="label">
                                <array key="de">
                                    <string>DDB-Viewer</string>
                                </array>
                            </map>
                            <string key="format">text/html</string>
                        </map>
                    </xsl:if>
                </array>
            </xsl:if>
            <!-- Ohne erzeugten primären Canvas verweist start auf den ersten verfügbaren Canvas. -->
            <xsl:if test="exists($canvasIds)">
                <map key="start">
                    <string key="id">
                        <xsl:value-of select="($canvasIds[. = $primaryCanvasId], $canvasIds)[1]" />
                    </string>
                    <string key="type">Canvas</string>
                </map>
            </xsl:if>
            <array key="items">
                <xsl:sequence select="$canvases" />
            </array>
            <!-- Die Übersicht enthält eine Range pro verfügbarem Canvas in Cortex-Reihenfolge. -->
            <xsl:if test="exists($canvases)">
                <array key="structures">
                    <map>
                        <string key="id">
                            <xsl:value-of select="ddblabs:resource-id('/range/r0')" />
                        </string>
                        <string key="type">Range</string>
                        <map key="label">
                            <array key="de">
                                <string>Übersicht</string>
                            </array>
                            <array key="en">
                                <string>Content</string>
                            </array>
                        </map>
                        <array key="items">
                            <xsl:for-each select="$binaries">
                                <xsl:variable name="canvasId" select="ddblabs:resource-id('/canvas/p' || position())" />
                                <xsl:if test="$canvasId = $canvasIds">
                                    <map>
                                        <string key="id">
                                            <xsl:value-of select="ddblabs:resource-id('/range/r' || position())" />
                                        </string>
                                        <string key="type">Range</string>
                                        <map key="label">
                                            <array key="de">
                                                <string>
                                                    <xsl:choose>
                                                        <xsl:when test="@name3 and string-length(@name3) > 0">
                                                            <xsl:value-of select="concat(@name, ' | ', @name2, ' | ', @name3)" />
                                                        </xsl:when>
                                                        <xsl:when test="@name2 and string-length(@name2) > 0">
                                                            <xsl:value-of select="concat(@name, ' | ', @name2)" />
                                                        </xsl:when>
                                                        <xsl:when test="@name and string-length(@name) > 0">
                                                            <xsl:value-of select="@name" />
                                                        </xsl:when>
                                                        <xsl:otherwise>
                                                            <xsl:text>Digitalisat </xsl:text>
                                                            <xsl:value-of select="position()" />
                                                        </xsl:otherwise>
                                                    </xsl:choose>
                                                </string>
                                            </array>
                                        </map>
                                        <array key="items">
                                            <map>
                                                <string key="id">
                                                    <xsl:value-of select="$canvasId" />
                                                </string>
                                                <string key="type">Canvas</string>
                                            </map>
                                        </array>
                                    </map>
                                </xsl:if>
                            </xsl:for-each>
                        </array>
                    </map>
                </array>
            </xsl:if>
        </map>
    </xsl:template>

    <!-- Canvas-Vorlagen nach Medientyp -->

    <!--
        JPEG-Canvases benötigen Breite und Höhe aus info.json des DDB-Bilddienstes.
        Fehlen gültige Maße, wird nur dieser Canvas ausgelassen. Die übrigen Medien bleiben darstellbar.
    -->
    <xsl:template match="/cortex:cortex/cortex:binaries/cortex:binary[@mimetype = 'image/jpeg']">
        <xsl:try>
            <xsl:variable name="infoJsonUrl">
                <xsl:text>https://iiif.deutsche-digitale-bibliothek.de/image/2/</xsl:text>
                <xsl:value-of select="encode-for-uri(string(@ref))" />
                <xsl:text>/info.json</xsl:text>
            </xsl:variable>
            <xsl:variable as="map(*)" name="infoJson" select="json-doc($infoJsonUrl)" />
            <xsl:variable as="xs:positiveInteger" name="imageWidth" select="xs:positiveInteger($infoJson?width)" />
            <xsl:variable as="xs:positiveInteger" name="imageHeight" select="xs:positiveInteger($infoJson?height)" />
            <map>
                <string key="id">
                    <xsl:value-of select="ddblabs:resource-id('/canvas/p' || position())" />
                </string>
                <string key="type">Canvas</string>
                <map key="label">
                    <array key="de">
                        <string>
                            <xsl:choose>
                                <xsl:when test="@name3 and string-length(@name3) > 0">
                                    <xsl:value-of select="concat(@name, ' | ', @name2, ' | ', @name3)" />
                                </xsl:when>
                                <xsl:when test="@name2 and string-length(@name2) > 0">
                                    <xsl:value-of select="concat(@name, ' | ', @name2)" />
                                </xsl:when>
                                <xsl:when test="@name and string-length(@name) > 0">
                                    <xsl:value-of select="@name" />
                                </xsl:when>
                                <xsl:otherwise>
                                    <xsl:text>Digitalisat </xsl:text>
                                    <xsl:value-of select="position()" />
                                </xsl:otherwise>
                            </xsl:choose>
                        </string>
                    </array>
                </map>
                <number key="height">
                    <xsl:value-of select="$imageHeight" />
                </number>
                <number key="width">
                    <xsl:value-of select="$imageWidth" />
                </number>
                <array key="items">
                    <map>
                        <string key="id">
                            <xsl:value-of select="ddblabs:resource-id('/canvas/p' || position() || '/1')" />
                        </string>
                        <string key="type">AnnotationPage</string>
                        <array key="items">
                            <map>
                                <string key="id">
                                    <xsl:value-of select="ddblabs:resource-id('/annotation/p000' || position() || '-image')" />
                                </string>
                                <string key="type">Annotation</string>
                                <string key="motivation">painting</string>
                                <map key="body">
                                    <string key="id">
                                        <xsl:text>https://iiif.deutsche-digitale-bibliothek.de/image/2/</xsl:text>
                                        <xsl:value-of select="@ref" />
                                        <xsl:text>/full/full/0/default.jpg</xsl:text>
                                    </string>
                                    <string key="type">Image</string>
                                    <string key="format">image/jpeg</string>
                                    <array key="service">
                                        <map>
                                            <string key="id">
                                                <xsl:text>https://iiif.deutsche-digitale-bibliothek.de/image/2/</xsl:text>
                                                <xsl:value-of select="@ref" />
                                            </string>
                                            <string key="type">ImageService2</string>
                                            <string key="profile">level2</string>
                                        </map>
                                    </array>
                                    <number key="height">
                                        <xsl:value-of select="$imageHeight" />
                                    </number>
                                    <number key="width">
                                        <xsl:value-of select="$imageWidth" />
                                    </number>
                                    <array key="metadata">
                                        <map>
                                            <map key="label">
                                                <array key="de">
                                                    <string>Beschreibung</string>
                                                </array>
                                            </map>
                                            <map key="value">
                                                <array key="de">
                                                    <string>
                                                        <xsl:choose>
                                                            <xsl:when test="@name3 and string-length(@name3) > 0">
                                                                <xsl:value-of select="concat(@name, ' | ', @name2, ' | ', @name3)" />
                                                            </xsl:when>
                                                            <xsl:when test="@name2 and string-length(@name2) > 0">
                                                                <xsl:value-of select="concat(@name, ' | ', @name2)" />
                                                            </xsl:when>
                                                            <xsl:when test="@name and string-length(@name) > 0">
                                                                <xsl:value-of select="@name" />
                                                            </xsl:when>
                                                            <xsl:otherwise>
                                                                <xsl:text>Digitalisat </xsl:text>
                                                                <xsl:value-of select="position()" />
                                                            </xsl:otherwise>
                                                        </xsl:choose>
                                                    </string>
                                                </array>
                                            </map>
                                        </map>
                                    </array>
                                </map>
                                <string key="target">
                                    <xsl:value-of select="ddblabs:resource-id('/canvas/p' || position())" />
                                </string>
                            </map>
                        </array>
                    </map>
                </array>
                <!-- Der Canvas verweist als Vorschau direkt auf denselben IIIF-Bilddienst. -->
                <array key="thumbnail">
                    <map>
                        <string key="id">
                            <xsl:text>https://iiif.deutsche-digitale-bibliothek.de/image/2/</xsl:text>
                            <xsl:value-of select="@ref" />
                            <xsl:text>/full/full/0/default.jpg</xsl:text>
                        </string>
                        <string key="type">Image</string>
                        <string key="format">image/jpeg</string>
                        <array key="service">
                            <map>
                                <string key="id">
                                    <xsl:text>https://iiif.deutsche-digitale-bibliothek.de/image/2/</xsl:text>
                                    <xsl:value-of select="@ref" />
                                </string>
                                <string key="type">ImageService2</string>
                                <string key="profile">level2</string>
                            </map>
                        </array>
                    </map>
                </array>
            </map>
            <xsl:catch errors="*" />
        </xsl:try>
    </xsl:template>

    <!-- PDF-Canvases verlinken das Originaldokument über den DDB-Binärdienst. -->
    <xsl:template match="/cortex:cortex/cortex:binaries/cortex:binary[@mimetype = 'application/pdf']">
        <map>
            <string key="id">
                <xsl:value-of select="ddblabs:resource-id('/canvas/p' || position())" />
            </string>
            <string key="type">Canvas</string>
            <map key="label">
                <array key="de">
                    <string>
                        <xsl:choose>
                            <xsl:when test="@name3 and string-length(@name3) > 0">
                                <xsl:value-of select="concat(@name, ' | ', @name2, ' | ', @name3)" />
                            </xsl:when>
                            <xsl:when test="@name2 and string-length(@name2) > 0">
                                <xsl:value-of select="concat(@name, ' | ', @name2)" />
                            </xsl:when>
                            <xsl:when test="@name and string-length(@name) > 0">
                                <xsl:value-of select="@name" />
                            </xsl:when>
                            <xsl:otherwise>
                                <xsl:text>Digitalisat </xsl:text>
                                <xsl:value-of select="position()" />
                            </xsl:otherwise>
                        </xsl:choose>
                    </string>
                </array>
            </map>
            <array key="items">
                <map>
                    <string key="id">
                        <xsl:value-of select="ddblabs:resource-id('/canvas/p' || position() || '/1')" />
                    </string>
                    <string key="type">AnnotationPage</string>
                    <array key="items">
                        <map>
                            <string key="id">
                                <xsl:value-of select="ddblabs:resource-id('/annotation/p000' || position() || '-document')" />
                            </string>
                            <string key="type">Annotation</string>
                            <string key="motivation">painting</string>
                            <map key="body">
                                <string key="id">
                                    <xsl:value-of select="$ddbBinaryBase || @ref || '.pdf'" />
                                </string>
                                <string key="type">Document</string>
                                <string key="format">application/pdf</string>
                                <array key="metadata">
                                    <map>
                                        <map key="label">
                                            <array key="de">
                                                <string>Beschreibung</string>
                                            </array>
                                        </map>
                                        <map key="value">
                                            <array key="de">
                                                <string>
                                                    <xsl:choose>
                                                        <xsl:when test="@name3 and string-length(@name3) > 0">
                                                            <xsl:value-of select="concat(@name, ' | ', @name2, ' | ', @name3)" />
                                                        </xsl:when>
                                                        <xsl:when test="@name2 and string-length(@name2) > 0">
                                                            <xsl:value-of select="concat(@name, ' | ', @name2)" />
                                                        </xsl:when>
                                                        <xsl:when test="@name and string-length(@name) > 0">
                                                            <xsl:value-of select="@name" />
                                                        </xsl:when>
                                                        <xsl:otherwise>
                                                            <xsl:text>Digitalisat </xsl:text>
                                                            <xsl:value-of select="position()" />
                                                        </xsl:otherwise>
                                                    </xsl:choose>
                                                </string>
                                            </array>
                                        </map>
                                    </map>
                                </array>
                            </map>
                            <string key="target">
                                <xsl:value-of select="ddblabs:resource-id('/canvas/p' || position())" />
                            </string>
                        </map>
                    </array>
                </map>
            </array>
            <!-- Die PDF-Referenz dient beim DDB-Bilddienst auch als ID des Vorschaubilds. -->
            <array key="thumbnail">
                <map>
                    <string key="id">
                        <xsl:text>https://iiif.deutsche-digitale-bibliothek.de/image/2/</xsl:text>
                        <xsl:value-of select="@ref" />
                        <xsl:text>/full/full/0/default.jpg</xsl:text>
                    </string>
                    <string key="type">Image</string>
                    <string key="format">image/jpeg</string>
                    <array key="service">
                        <map>
                            <string key="id">
                                <xsl:text>https://iiif.deutsche-digitale-bibliothek.de/image/2/</xsl:text>
                                <xsl:value-of select="@ref" />
                            </string>
                            <string key="type">ImageService2</string>
                            <string key="profile">level2</string>
                        </map>
                    </array>
                </map>
            </array>
        </map>
    </xsl:template>

    <!-- Video-Canvases binden die MP4-Datei aus dem DDB-Binärdienst als Painting-Annotation ein. -->
    <xsl:template match="/cortex:cortex/cortex:binaries/cortex:binary[@mimetype = 'video/mp4']">
        <map>
            <string key="id">
                <xsl:value-of select="ddblabs:resource-id('/canvas/p' || position())" />
            </string>
            <string key="type">Canvas</string>
            <map key="label">
                <array key="de">
                    <string>
                        <xsl:choose>
                            <xsl:when test="@name3 and string-length(@name3) > 0">
                                <xsl:value-of select="concat(@name, ' | ', @name2, ' | ', @name3)" />
                            </xsl:when>
                            <xsl:when test="@name2 and string-length(@name2) > 0">
                                <xsl:value-of select="concat(@name, ' | ', @name2)" />
                            </xsl:when>
                            <xsl:when test="@name and string-length(@name) > 0">
                                <xsl:value-of select="@name" />
                            </xsl:when>
                            <xsl:otherwise>
                                <xsl:text>Digitalisat </xsl:text>
                                <xsl:value-of select="position()" />
                            </xsl:otherwise>
                        </xsl:choose>
                    </string>
                </array>
            </map>
            <array key="items">
                <map>
                    <string key="id">
                        <xsl:value-of select="ddblabs:resource-id('/canvas/p' || position() || '/1')" />
                    </string>
                    <string key="type">AnnotationPage</string>
                    <array key="items">
                        <map>
                            <string key="id">
                                <xsl:value-of select="ddblabs:resource-id('/annotation/p000' || position() || '-video')" />
                            </string>
                            <string key="type">Annotation</string>
                            <string key="motivation">painting</string>
                            <map key="body">
                                <string key="id">
                                    <xsl:value-of select="$ddbBinaryBase || @ref || '.mp4'" />
                                </string>
                                <string key="type">Video</string>
                                <string key="format">video/mp4</string>
                            </map>
                            <string key="target">
                                <xsl:value-of select="ddblabs:resource-id('/canvas/p' || position())" />
                            </string>
                        </map>
                    </array>
                </map>
            </array>
            <!-- Die Cortex-Position ordnet dem Video ein separat geliefertes Vorschaubild zu. -->
            <xsl:if test="/cortex:cortex/cortex:binaries/cortex:binary[@position = current()/@position and @mimetype = 'image/jpeg']/@ref">
                <array key="thumbnail">
                    <map>
                        <string key="id">
                            <xsl:text>https://iiif.deutsche-digitale-bibliothek.de/image/2/</xsl:text>
                            <xsl:value-of select="/cortex:cortex/cortex:binaries/cortex:binary[@position = current()/@position and @mimetype = 'image/jpeg']/@ref" />
                            <xsl:text>/full/full/0/default.jpg</xsl:text>
                        </string>
                        <string key="type">Image</string>
                        <string key="format">image/jpeg</string>
                        <array key="service">
                            <map>
                                <string key="id">
                                    <xsl:text>https://iiif.deutsche-digitale-bibliothek.de/image/2/</xsl:text>
                                    <xsl:value-of select="/cortex:cortex/cortex:binaries/cortex:binary[@position = current()/@position and @mimetype = 'image/jpeg']/@ref" />
                                </string>
                                <string key="type">ImageService2</string>
                                <string key="profile">level2</string>
                            </map>
                        </array>
                    </map>
                </array>
            </xsl:if>
        </map>
    </xsl:template>

    <!-- Audiodateien des Typs audio/mpeg werden als MP3 über den DDB-Binärdienst verlinkt. -->
    <xsl:template match="/cortex:cortex/cortex:binaries/cortex:binary[@mimetype = 'audio/mpeg']">
        <map>
            <string key="id">
                <xsl:value-of select="ddblabs:resource-id('/canvas/p' || position())" />
            </string>
            <string key="type">Canvas</string>
            <map key="label">
                <array key="de">
                    <string>
                        <xsl:choose>
                            <xsl:when test="@name3 and string-length(@name3) > 0">
                                <xsl:value-of select="concat(@name, ' | ', @name2, ' | ', @name3)" />
                            </xsl:when>
                            <xsl:when test="@name2 and string-length(@name2) > 0">
                                <xsl:value-of select="concat(@name, ' | ', @name2)" />
                            </xsl:when>
                            <xsl:when test="@name and string-length(@name) > 0">
                                <xsl:value-of select="@name" />
                            </xsl:when>
                            <xsl:otherwise>
                                <xsl:text>Digitalisat </xsl:text>
                                <xsl:value-of select="position()" />
                            </xsl:otherwise>
                        </xsl:choose>
                    </string>
                </array>
            </map>
            <array key="items">
                <map>
                    <string key="id">
                        <xsl:value-of select="ddblabs:resource-id('/canvas/p' || position() || '/1')" />
                    </string>
                    <string key="type">AnnotationPage</string>
                    <array key="items">
                        <map>
                            <string key="id">
                                <xsl:value-of select="ddblabs:resource-id('/annotation/p000' || position() || '-sound')" />
                            </string>
                            <string key="type">Annotation</string>
                            <string key="motivation">painting</string>
                            <map key="body">
                                <string key="id">
                                    <xsl:value-of select="$ddbBinaryBase || @ref || '.mp3'" />
                                </string>
                                <string key="type">Sound</string>
                                <string key="format">audio/mpeg</string>
                            </map>
                            <string key="target">
                                <xsl:value-of select="ddblabs:resource-id('/canvas/p' || position())" />
                            </string>
                        </map>
                    </array>
                </map>
            </array>
            <!-- Wenn ein JPEG dieselbe Cortex-Position hat, dient es als Audiovorschau. -->
            <xsl:if test="/cortex:cortex/cortex:binaries/cortex:binary[@position = current()/@position and @mimetype = 'image/jpeg']/@ref">
                <array key="thumbnail">
                    <map>
                        <string key="id">
                            <xsl:text>https://iiif.deutsche-digitale-bibliothek.de/image/2/</xsl:text>
                            <xsl:value-of select="/cortex:cortex/cortex:binaries/cortex:binary[@position = current()/@position and @mimetype = 'image/jpeg']/@ref" />
                            <xsl:text>/full/full/0/default.jpg</xsl:text>
                        </string>
                        <string key="type">Image</string>
                        <string key="format">image/jpeg</string>
                        <array key="service">
                            <map>
                                <string key="id">
                                    <xsl:text>https://iiif.deutsche-digitale-bibliothek.de/image/2/</xsl:text>
                                    <xsl:value-of select="/cortex:cortex/cortex:binaries/cortex:binary[@position = current()/@position and @mimetype = 'image/jpeg']/@ref" />
                                </string>
                                <string key="type">ImageService2</string>
                                <string key="profile">level2</string>
                            </map>
                        </array>
                    </map>
                </array>
            </xsl:if>
        </map>
    </xsl:template>
    <!-- Die leere Standardvorlage verwirft freie Textknoten und Attribute aus der Cortex-Quelle. -->
    <xsl:template match="text() | @*" />
</xsl:stylesheet>
