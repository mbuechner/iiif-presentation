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
    <xsl:output encoding="UTF-8" method="xml" />
    <!-- uri of this record -->
    <xsl:param name="uri">https://labs.deutsche-digitale-bibliothek.de/iiif/presentation/3/ABCDEFGHIJKLMNOPQRSTUVWXYZ012345</xsl:param>
    <xsl:function name="ddblabs:resource-id" as="xs:string">
        <xsl:param name="path" as="xs:string" />
        <xsl:sequence select="
                if (contains($uri, '?'))
                then substring-before($uri, '?') || $path || '?' || substring-after($uri, '?')
                else $uri || $path" />
    </xsl:function>

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

    <!-- root template -->
    <xsl:template match="/">
        <!-- variables -->
        <!-- id of this record -->
        <xsl:variable name="id">
            <xsl:value-of select="/cortex:cortex/cortex:properties/cortex:item-id" />
        </xsl:variable>
        <xsl:variable name="provider" select="/cortex:cortex/cortex:provider-info[1]" />
        <xsl:variable name="providerId" select="normalize-space($provider/cortex:provider-ddb-id[1])" />
        <xsl:variable name="providerName" select="normalize-space($provider/cortex:provider-name[1])" />
        <xsl:variable name="providerLogo" as="xs:string?">
            <xsl:if test="$providerId and $providerName">
                <xsl:try>
                    <xsl:variable name="providerUrl" select="'https://api.deutsche-digitale-bibliothek.de/2/items/' || encode-for-uri($providerId)" />
                    <xsl:sequence select="(doc($providerUrl)/cortex:cortex/cortex:binaries/cortex:binary[@primary = 'true']/@ref)[1] ! string(.)" />
                    <xsl:catch />
                </xsl:try>
            </xsl:if>
        </xsl:variable>
        <xsl:variable name="binaries" select="/cortex:cortex/cortex:binaries/cortex:binary[@mimetype = ('image/jpeg', 'application/pdf', 'video/mp4', 'audio/mpeg')]" />
        <xsl:variable name="canvases" as="element(j:map)*">
            <xsl:apply-templates select="$binaries" />
        </xsl:variable>
        <xsl:variable name="canvasIds" select="$canvases/j:string[@key = 'id']/string()" />
        <xsl:variable name="primaryCanvasId" select="ddblabs:resource-id('/canvas/p' || index-of($binaries ! string(@primary), 'true')[1])" />
        <!-- start of record -->
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
            <!-- metadata block -->
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
            <!-- summary block -->
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
            <!-- thumbnail block -->
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
            <!-- viewingDirection (hard coded) -->
            <string key="viewingDirection">left-to-right</string>
            <!-- behavior (hard coded) -->
            <array key="behavior">
                <string>individuals</string>
            </array>
            <!-- rights of metadata -->
            <string key="rights">
                <xsl:value-of select="/cortex:cortex/cortex:view/ns4:item/ns4:license/@ns3:resource" />
            </string>
            <!-- requiredStatement -->
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
            <!-- provider -->
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
            <!-- homepage -->
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
            <!-- logo -->
            <!-- TODO: logo at this position is not IIIF Presentation v3 valid, but Mirador 3 will display a logo (which is nice) -->
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
            <!-- seeAlso -->
            <array key="seeAlso">
                <map>
                    <string key="id">
                        <xsl:text>https://api.deutsche-digitale-bibliothek.de/items/</xsl:text>
                        <xsl:value-of select="$id" />
                    </string>
                    <string key="type">Dataset</string>
                    <string key="format">application/xml</string>
                    <string key="profile">https://www.deutsche-digitale-bibliothek.de/ns/cortex</string>
                </map>
            </array>
            <!-- rendering -->
            <!-- 
            "rendering": [
                {
                    "id": "https://api.deutsche-digitale-bibliothek.de/binary/8fac26ef-8b2d-47ef-94c3-259326c82ac4.pdf",
                    "type": "Text",
                    "label":
                    {
                        "de": ["PDF-Ansicht"]
                    },
                    "format": "application/pdf"
                }
            ],
            -->
            <xsl:if test="/cortex:cortex/cortex:binaries/cortex:binary[@mimetype = 'application/pdf'] or /cortex:cortex/cortex:binaries/cortex:binary[@mimetype = 'video/vnd.ddbkultur.vimeo'] or /cortex:cortex/source:source/source:description/ns5:record/ns5:id[@type = 'mets:div/@ID']/@value">
                <array key="rendering">
                    <!-- PDF -->
                    <xsl:if test="/cortex:cortex/cortex:binaries/cortex:binary[@mimetype = 'application/pdf']">
                        <xsl:for-each select="/cortex:cortex/cortex:binaries/cortex:binary[@mimetype = 'application/pdf']">
                            <map>
                                <string key="id">
                                    <xsl:text>https://api.deutsche-digitale-bibliothek.de/binary/</xsl:text>
                                    <xsl:value-of select="@ref" />
                                    <xsl:text>.pdf</xsl:text>
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
                    <!-- Vimeo-Video -->
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
                    <!-- DFG-Viewer -->
                    <xsl:if test="/cortex:cortex/source:source/source:description/ns5:record/ns5:id[@type = 'mets:div/@ID']/@value">
                        <map>
                            <string key="id">
                                <xsl:text>https://viewer.deutsche-digitale-bibliothek.de/index.php?id=1&amp;tx_dlf[id]=https%3A%2F%2Fapi.deutsche-digitale-bibliothek.de%2Fitems%2F</xsl:text>
                                <xsl:value-of select="/cortex:cortex/source:source/source:description/ns5:record/@ref" />
                                <xsl:text>%2Fsource%2Frecord&amp;tx_dlf[page]=</xsl:text>
                                <xsl:value-of select="/cortex:cortex/source:source/source:description/ns5:record/ns5:id[@type = 'mets:div/@ID']/@value" />
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
            <!-- structures -->
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
            <!--  -->
        </map>
    </xsl:template>
    <!-- template for images -->
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
                            <!-- images and pdf (pdf always have a preview image) -->
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
                <!-- thumbnail -->
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
    <!-- template for pdf -->
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
                                    <xsl:text>https://api.deutsche-digitale-bibliothek.de/binary/</xsl:text>
                                    <xsl:value-of select="@ref" />
                                    <xsl:text>.pdf</xsl:text>
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
            <!-- thumbnail, because every PDF does have a thumbnail -->
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
    <!-- template for video -->
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
            <!-- we don't know the duration, resolution etc. and we'll never know -->
            <!-- <number key="height">360</number> -->
            <!-- <number key="width">480</number> -->
            <!-- <number key="duration">321.0</number> -->
            <array key="items">
                <map>
                    <string key="id">
                        <xsl:value-of select="ddblabs:resource-id('/canvas/p' || position() || '/1')" />
                    </string>
                    <string key="type">AnnotationPage</string>
                    <array key="items">
                        <!-- videos -->
                        <map>
                            <string key="id">
                                <xsl:value-of select="ddblabs:resource-id('/annotation/p000' || position() || '-video')" />
                            </string>
                            <string key="type">Annotation</string>
                            <string key="motivation">painting</string>
                            <map key="body">
                                <string key="id">
                                    <xsl:text>https://api.deutsche-digitale-bibliothek.de/binary/</xsl:text>
                                    <xsl:value-of select="@ref" />
                                    <xsl:text>.mp4</xsl:text>
                                </string>
                                <string key="type">Video</string>
                                <!-- we don't know the duration, resolution etc. and we'll never know -->
                                <!-- <number key="height">360</number> -->
                                <!-- <number key="width">480</number> -->
                                <!-- <number key="duration">321.0</number> -->
                                <string key="format">video/mp4</string>
                            </map>
                            <string key="target">
                                <xsl:value-of select="ddblabs:resource-id('/canvas/p' || position())" />
                            </string>
                        </map>
                    </array>
                </map>
            </array>
            <!-- thumbnail, because every video does have a thumbnail -->
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
    <!-- template for audio -->
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
                        <!-- audio -->
                        <map>
                            <string key="id">
                                <xsl:value-of select="ddblabs:resource-id('/annotation/p000' || position() || '-sound')" />
                            </string>
                            <string key="type">Annotation</string>
                            <string key="motivation">painting</string>
                            <map key="body">
                                <string key="id">
                                    <xsl:text>https://api.deutsche-digitale-bibliothek.de/binary/</xsl:text>
                                    <xsl:value-of select="@ref" />
                                    <xsl:text>.mp3</xsl:text>
                                </string>
                                <string key="type">Sound</string>
                                <!-- <number key="duration">96.0</number> -->
                                <string key="format">audio/mpeg</string>
                            </map>
                            <string key="target">
                                <xsl:value-of select="ddblabs:resource-id('/canvas/p' || position())" />
                            </string>
                        </map>
                    </array>
                </map>
            </array>
            <!-- thumbnail, because audio may have a thumbnail -->
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
    <!-- default template -->
    <xsl:template match="text() | @*" />
</xsl:stylesheet>
