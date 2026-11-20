<?xml version="1.0" encoding="UTF-8"?>
<!-- 
Copyright 2025 Michael Büchner, Deutsche Digitale Bibliothek

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
<xsl:stylesheet version="3.0"
        xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
        xmlns:xs="http://www.w3.org/2001/XMLSchema"
        xmlns:array="http://www.w3.org/2005/xpath-functions/array"
        xmlns:map="http://www.w3.org/2005/xpath-functions/map"
        xmlns:cortex="http://www.deutsche-digitale-bibliothek.de/cortex"
        xmlns:ddblabs="https://labs.deutsche-digitale-bibliothek.de"
        xmlns:mets="http://www.loc.gov/METS/"
        xmlns:mix="http://www.loc.gov/mix/v20"
        xmlns:mods="http://www.loc.gov/mods/v3"
        xmlns:oai="http://www.openarchives.org/OAI/2.0/"
        xmlns:saxon="http://saxon.sf.net/"
        xmlns:xlink="http://www.w3.org/1999/xlink">

    <!--
        Erzeugt ein Manifest nach IIIF Presentation API 3.0 aus einem METS/MODS-Dokument.
        MODS liefert Titel, Rechte und Zuschreibung. Die PHYSICAL-Gliederung liefert
        die Seiten in Lesereihenfolge, fileSec ihre Bilddateien und amdSec die MIX-Metadaten.
        Die LOGICAL-Gliederung bildet das Inhaltsverzeichnis. structLink verbindet
        dessen Abschnitte mit den angezeigten Seiten.
    -->
    <xsl:output method="json" encoding="UTF-8" indent="yes" use-character-maps="no-escape-slash" />
    <xsl:strip-space elements="*" />
    <xsl:character-map name="no-escape-slash">
        <xsl:output-character character="/" string="/" />
    </xsl:character-map>

    <!--
        Der Controller übergibt die DDB-Objekt-ID und die öffentliche Manifest-URL.
        Die Beispielwerte ermöglichen einen eigenständigen Testlauf des Stylesheets.
        Angaben zur liefernden Einrichtung kommen optional aus dem Cortex-Datensatz.
    -->
    <xsl:param name="itemId" as="xs:string" select="'TTNVQWVXY3AKILUHHULXB5H2ZHZGEKOO'" />
    <xsl:param name="itemUrl" as="xs:string"
            select="'https://iiif.deutsche-digitale-bibliothek.de/presentation/3/TTNVQWVXY3AKILUHHULXB5H2ZHZGEKOO'" />
    <xsl:param name="providerInfo" as="element(cortex:provider-info)?" select="()" />

    <!-- Die Indizes lösen Dateizeiger und Strukturverweise im gesamten METS-Dokument auf. -->
    <xsl:key name="fileById" match="mets:file" use="@ID" />
    <xsl:key name="linksBySource" match="mets:smLink" use="@xlink:from" />

    <xsl:variable name="document" as="document-node()" select="/" />
    <xsl:variable name="fileSection" as="element(mets:fileSec)?" select="/mets:mets/mets:fileSec" />
    <xsl:variable name="fileGroups" as="element(mets:fileGrp)*" select="$fileSection/mets:fileGrp" />
    <xsl:variable name="administrativeSections" as="element(mets:amdSec)*" select="/mets:mets/mets:amdSec" />

    <!--
        Kitodo kennzeichnet IIIF-Dateien per MIME-Typ. Andere Lieferungen erkennt man
        an der üblichen Bildanfrage mit /full/max/0/default.jpg oder /full/full/0/default.jpg.
        Bei gleichzeitiger Kennzeichnung hat Kitodo Vorrang. Für direkte Bilddateien
        wird MAX vor DEFAULT verwendet, für Vorschaubilder MIN vor DEFAULT.
    -->
    <xsl:variable name="imageServiceGroup" as="element(mets:fileGrp)?" select="(
            $fileGroups[mets:file[@MIMETYPE = 'application/vnd.kitodo.iiif']],
            $fileGroups[mets:file/mets:FLocat[matches(@xlink:href, '/full/(max|full)/0/default\.jpg(\?|$)')]]
        )[1]" />
    <xsl:variable name="usesImageService" as="xs:boolean" select="exists($imageServiceGroup)" />
    <xsl:variable name="imageGroupUse" as="xs:string" select="string((
            $imageServiceGroup/@USE, $fileGroups[@USE = 'MAX']/@USE, $fileGroups[@USE = 'DEFAULT']/@USE
        )[1])" />
    <xsl:variable name="thumbnailGroupUse" as="xs:string" select="string((
            $imageServiceGroup/@USE, $fileGroups[@USE = 'MIN']/@USE, $fileGroups[@USE = 'DEFAULT']/@USE
        )[1])" />

    <!-- Ein Canvas braucht eine Seiten-ID und eine verlinkte Bilddatei aus der gewählten Gruppe. -->
    <xsl:variable name="renderablePages" as="element(mets:div)*" select="
            /mets:mets/mets:structMap[@TYPE = 'PHYSICAL']/mets:div/mets:div[@TYPE = 'page'][@ID]
                [ddblabs:page-file(., $imageGroupUse)/mets:FLocat/@xlink:href[normalize-space(.)]]
        " />

    <!-- Manifest und MODS-Metadaten -->

    <xsl:template match="/">
        <xsl:variable name="canvases" as="map(*)*" select="
                for $position in 1 to count($renderablePages)
                return ddblabs:build-canvas($renderablePages[$position], $position)
            " />
        <xsl:map>
            <xsl:call-template name="manifest-metadata" />
            <!-- Die Vorschau des ersten Canvas wiederverwenden, damit info.json nur einmal abgerufen wird. -->
            <xsl:if test="exists($canvases)">
                <xsl:map-entry key="'thumbnail'" select="$canvases[1]?thumbnail" />
            </xsl:if>
            <xsl:map-entry key="'items'" select="array { $canvases }" />
        </xsl:map>
    </xsl:template>

    <xsl:template name="manifest-metadata">
        <xsl:variable name="mods" select="/mets:mets/mets:dmdSec[1]/mets:mdWrap/mets:xmlData/mods:mods" />

        <xsl:map-entry key="'@context'" select="'http://iiif.io/api/presentation/3/context.json'" />
        <xsl:map-entry key="'id'" select="$itemUrl" />
        <xsl:map-entry key="'type'" select="'Manifest'" />

        <!-- Der Titel des übergeordneten Werks steht in relatedItem, etwa bei einem Zeitungsheft. -->
        <xsl:variable name="titles" select="$mods/mods:relatedItem/mods:titleInfo/mods:title" />
        <xsl:if test="$titles">
            <xsl:map-entry key="'label'" select="map { 'de': array { $titles/text() } }" />
        </xsl:if>
        <xsl:map-entry key="'viewingDirection'" select="'left-to-right'" />
        <xsl:map-entry key="'behavior'" select="['individuals']" />

        <xsl:variable name="license" select="$mods/mods:recordInfo/mods:recordInfoNote[@type = 'license']" />
        <xsl:if test="$license">
            <xsl:map-entry key="'rights'" select="string($license)" />
        </xsl:if>

        <!--
            Die Zuschreibung nennt vorrangig den Verlag aus dem Digitalisierungsereignis.
            Fehlt dieses Ereignis, gilt der erste originInfo-Eintrag ohne eventType.
            Eine MODS-PURL kann den Namen als Link zum Original ergänzen.
        -->
        <xsl:variable name="digitization" select="$mods/mods:originInfo[@eventType = 'digitization']" />
        <xsl:variable name="publisher" as="xs:string" select="
                if (exists($digitization)) then string($digitization/mods:publisher[1])
                else string($mods/mods:originInfo[not(@eventType)][1]/mods:publisher[1])
            " />
        <xsl:variable name="attribution" as="xs:string" select="
                ddblabs:generate-link($publisher, $mods/mods:identifier[@type = 'purl'][1], true())
            " />
        <xsl:if test="$attribution">
            <xsl:map-entry key="'requiredStatement'" select="map {
                    'label': map { 'en': ['Attribution'], 'de': ['Zuschreibung'] },
                    'value': map { 'none': [$attribution] }
                }" />
        </xsl:if>

        <xsl:call-template name="manifest-provider" />

        <!-- homepage verweist auf die Objektseite, seeAlso auf die maschinenlesbaren Cortex-Metadaten. -->
        <xsl:map-entry key="'homepage'" select="[map {
                'id': 'https://www.deutsche-digitale-bibliothek.de/item/' || $itemId,
                'type': 'Text',
                'label': map { 'de': ['Deutsche Digitale Bibliothek'], 'en': ['German Digitale Library'] },
                'format': 'text/html'
            }]" />
        <xsl:map-entry key="'seeAlso'" select="[map {
                'id': 'https://api.deutsche-digitale-bibliothek.de/2/items/' || $itemId,
                'type': 'Dataset',
                'format': 'application/xml',
                'profile': 'https://www.deutsche-digitale-bibliothek.de/ns/cortex'
            }]" />

        <!-- ORDER=1 hat beim Einstieg Vorrang. Sonst beginnt die Anzeige mit der ersten verfügbaren Seite. -->
        <xsl:variable name="startPage" select="($renderablePages[@ORDER = '1'], $renderablePages)[1]" />
        <xsl:if test="$startPage">
            <xsl:map-entry key="'start'" select="ddblabs:canvas-reference(string($startPage/@ID))" />
        </xsl:if>

        <xsl:map-entry key="'structures'" select="array {
                /mets:mets/mets:structMap[@TYPE = 'LOGICAL']/mets:div ! ddblabs:build-range(.)
            }" />
    </xsl:template>

    <!-- Der Cortex-Provider ist optional. Eine DDB-Organisations-ID und ein Name bilden den Agent. -->
    <xsl:template name="manifest-provider">
        <xsl:variable name="idNodes" select="$providerInfo/cortex:provider-ddb-id" />
        <xsl:variable name="nameNodes" select="$providerInfo/cortex:provider-name" />

        <xsl:if test="normalize-space($idNodes[1]) and normalize-space($nameNodes[1])">
            <xsl:variable name="name" select="string($nameNodes)" />
            <xsl:variable name="organisationUrl" select="
                    'https://www.deutsche-digitale-bibliothek.de/organization/' || string($idNodes)
                " />
            <xsl:variable name="homepage" select="string($providerInfo/cortex:provider-uri)" />
            <xsl:variable name="logo" select="string($providerInfo/cortex:provider-logo)" />

            <xsl:variable name="agent" as="map(*)">
                <xsl:map>
                    <xsl:map-entry key="'id'" select="$organisationUrl" />
                    <xsl:map-entry key="'type'" select="'Agent'" />
                    <xsl:map-entry key="'label'" select="map { 'none': [$name] }" />
                    <xsl:map-entry key="'seeAlso'" select="[map {
                            'id': $organisationUrl,
                            'type': 'Text',
                            'label': map { 'de': [$name || ' bei der Deutschen Digitalen Bibliothek'] }
                        }]" />
                    <xsl:if test="$logo">
                        <!-- Cortex liefert keine Logomaße. Die Bildangabe verwendet die bisherigen Standardmaße. -->
                        <xsl:variable name="format" select="
                                if (matches($logo, '\.jpe?g$', 'i')) then 'image/jpeg'
                                else if (ends-with(lower-case($logo), '.png')) then 'image/png'
                                else 'application/octet-stream'
                            " />
                        <xsl:map-entry key="'logo'" select="[map {
                                'id': $logo,
                                'type': 'Image',
                                'width': 1600,
                                'height': 1200,
                                'format': $format
                            }]" />
                    </xsl:if>
                    <xsl:if test="$homepage">
                        <xsl:map-entry key="'homepage'" select="[map {
                                'id': $homepage,
                                'type': 'Text',
                                'label': map { 'none': [$name] },
                                'format': 'text/html'
                            }]" />
                    </xsl:if>
                </xsl:map>
            </xsl:variable>
            <xsl:map-entry key="'provider'" select="[$agent]" />
        </xsl:if>
    </xsl:template>

    <!-- Physische Seiten und ihre Dateien -->

    <!-- fptr/@FILEID verweist auf mets:file/@ID. @USE der Dateigruppe bestimmt die Rolle der Datei. -->
    <xsl:function name="ddblabs:page-file" as="element(mets:file)?">
        <xsl:param name="page" as="element(mets:div)" />
        <xsl:param name="groupUse" as="xs:string" />

        <xsl:variable name="files" select="key('fileById', $page/mets:fptr/@FILEID, $document)" />
        <xsl:sequence select="$files[ancestor::mets:fileGrp[1][string(@USE) = $groupUse]][1]" />
    </xsl:function>

    <xsl:function name="ddblabs:file-url" as="xs:string">
        <xsl:param name="file" as="element(mets:file)?" />
        <xsl:sequence select="normalize-space(($file/mets:FLocat/@xlink:href)[1])" />
    </xsl:function>

    <!--
        Eine darstellbare PHYSICAL-Seite wird zum Canvas mit Bildannotation und Vorschau.
        Die Position ist die laufende Nummer im Manifest. Sie dient als Beschriftung,
        wenn METS weder ORDER noch ORDERLABEL liefert.
    -->
    <xsl:function name="ddblabs:build-canvas" as="map(*)">
        <xsl:param name="page" as="element(mets:div)" />
        <xsl:param name="position" as="xs:integer" />

        <xsl:variable name="canvasPath" select="ddblabs:canvas-path(string($page/@ID))" />
        <xsl:variable name="canvasId" select="ddblabs:append-path($itemUrl, $canvasPath)" />
        <xsl:variable name="imageFile" select="ddblabs:page-file($page, $imageGroupUse)" />
        <xsl:variable name="imageUrl" select="ddblabs:file-url($imageFile)" />
        <xsl:variable name="serviceUrl" select="ddblabs:iiif-base-url($imageUrl)" />
        <xsl:variable name="imageInfo" select="
                if ($usesImageService) then ddblabs:read-image-info(ddblabs:append-path($serviceUrl, '/info.json'))
                else ()
            " />

        <!--
            Maße aus info.json haben Vorrang. Dateibezogene MIX-Maße stehen in techMD
            und werden über die IDs in ADMID gefunden. 1600 × 1200 ist die letzte
            Rückfallgröße, damit der Canvas auch ohne Maßangaben verwendbar bleibt.
        -->
        <xsl:variable name="technicalIds" select="tokenize(normalize-space($imageFile/@ADMID), '\s+')" />
        <xsl:variable name="mixCharacteristics" select="
                $administrativeSections/mets:techMD[@ID = $technicalIds]/mets:mdWrap/mets:xmlData
                    /mix:mix/mix:BasicImageInformation/mix:BasicImageCharacteristics
            " />
        <xsl:variable name="width" select="(
                $imageInfo?width,
                $mixCharacteristics/mix:imageWidth[. castable as xs:positiveInteger] ! xs:positiveInteger(.),
                1600
            )[1]" />
        <xsl:variable name="height" select="(
                $imageInfo?height,
                $mixCharacteristics/mix:imageHeight[. castable as xs:positiveInteger] ! xs:positiveInteger(.),
                1200
            )[1]" />

        <!--
            Bei fehlendem info.json bleibt eine vorhandene Bildanfrage samt Query erhalten.
            Steht in METS nur die Basis- oder Info-URL, wird daraus eine JPEG-Bildanfrage.
        -->
        <xsl:variable name="fallbackImageUrl" select="
                if ($usesImageService and ($imageUrl = $serviceUrl or matches($imageUrl, '/info\.json(\?|$)')))
                then ddblabs:append-path($serviceUrl, '/full/full/0/default.jpg')
                else $imageUrl
            " />
        <xsl:variable name="paintingBody" as="map(*)" select="
                if (exists($imageInfo)) then ddblabs:iiif-image($serviceUrl, $imageInfo, ())
                else map {
                    'id': $fallbackImageUrl,
                    'type': 'Image',
                    'format': if ($usesImageService) then 'image/jpeg' else string($imageFile/@MIMETYPE),
                    'width': $width,
                    'height': $height
                }
            " />

        <!-- Der Bilddienst liefert eine verkleinerte Vorschau. Bei direkten Dateien hat eine eigene Vorschau Vorrang. -->
        <xsl:variable name="thumbnailFile" select="ddblabs:page-file($page, $thumbnailGroupUse)" />
        <xsl:variable name="thumbnailUrl" select="ddblabs:file-url($thumbnailFile)" />
        <xsl:variable name="thumbnail" as="map(*)" select="
                if (exists($imageInfo)) then
                    ddblabs:iiif-image($serviceUrl, $imageInfo, ddblabs:thumbnail-dimensions($width, $height))
                else if (not($usesImageService) and $thumbnailUrl and $thumbnailUrl ne $imageUrl) then map {
                    'id': $thumbnailUrl,
                    'type': 'Image',
                    'format': string($thumbnailFile/@MIMETYPE)
                }
                else $paintingBody
            " />
        <xsl:variable name="fulltextUrl" select="ddblabs:file-url(ddblabs:page-file($page, 'DDB_FULLTEXT'))" />

        <xsl:variable name="order" select="normalize-space($page/@ORDER)" />
        <xsl:variable name="orderLabel" select="normalize-space($page/@ORDERLABEL)" />
        <xsl:variable name="label" select="
                if ($order and $orderLabel) then $order || ' (' || $orderLabel || ')'
                else ($order[.], $orderLabel[.], string($position))[1]
            " />
        <xsl:variable name="paintingAnnotation" as="map(*)" select="map {
                'id': ddblabs:append-path($itemUrl, $canvasPath || '/annotation/1'),
                'type': 'Annotation',
                'motivation': 'painting',
                'body': $paintingBody,
                'target': $canvasId
            }" />

        <xsl:map>
            <xsl:map-entry key="'id'" select="$canvasId" />
            <xsl:map-entry key="'type'" select="'Canvas'" />
            <xsl:map-entry key="'height'" select="$height" />
            <xsl:map-entry key="'width'" select="$width" />
            <xsl:map-entry key="'label'" select="map { 'none': [$label] }" />
            <xsl:map-entry key="'items'" select="[map {
                    'id': ddblabs:append-path($itemUrl, $canvasPath || '/1'),
                    'type': 'AnnotationPage',
                    'items': [$paintingAnnotation]
                }]" />
            <xsl:map-entry key="'thumbnail'" select="[$thumbnail]" />
            <!-- Die Gruppe DDB_FULLTEXT enthält seitenbezogene ALTO-Dateien für OCR-Volltext. -->
            <xsl:if test="$fulltextUrl">
                <xsl:map-entry key="'seeAlso'" select="[map {
                        'id': $fulltextUrl,
                        'type': 'Dataset',
                        'format': 'application/xml+alto',
                        'profile': 'http://www.loc.gov/standards/alto/'
                    }]" />
            </xsl:if>
        </xsl:map>
    </xsl:function>

    <!-- Logisches Inhaltsverzeichnis -->

    <!--
        Jeder LOGICAL-Abschnitt wird zu einem Range. Zuerst folgen die untergeordneten
        Ranges, danach die über structLink (from → to) verknüpften Canvas-Referenzen.
        Nur erzeugte Canvases werden referenziert. Mehrfache Verweise auf dieselbe
        Seite werden innerhalb eines Range zusammengefasst. Ein Abschnitt ohne
        Unterabschnitt oder Canvas bleibt als leerer Range im Inhaltsverzeichnis.
    -->
    <xsl:function name="ddblabs:build-range" as="map(*)">
        <xsl:param name="division" as="element(mets:div)" />

        <xsl:variable name="id" select="string($division/@ID)" />
        <xsl:variable name="label" select="normalize-space($division/@LABEL)" />
        <xsl:variable name="orderLabel" select="normalize-space($division/@ORDERLABEL)" />
        <xsl:variable name="displayLabel" select="
                if ($label and $orderLabel) then $label || ' (' || $orderLabel || ')'
                else if ($label) then $label
                else $orderLabel
            " />

        <xsl:variable name="targets" select="key('linksBySource', $id, $document) ! string(@xlink:to)" />
        <xsl:variable name="childRanges" select="$division/mets:div ! ddblabs:build-range(.)" />
        <xsl:variable name="canvasReferences" select="
                distinct-values($targets[. = $renderablePages/@ID]) ! ddblabs:canvas-reference(.)
            " />

        <xsl:sequence select="map {
                'id': ddblabs:append-path($itemUrl, '/range/' || encode-for-uri($id)),
                'type': 'Range',
                'label': map { 'none': [$displayLabel] },
                'items': array { $childRanges, $canvasReferences }
            }" />
    </xsl:function>

    <xsl:function name="ddblabs:canvas-path" as="xs:string">
        <xsl:param name="pageId" as="xs:string" />
        <xsl:sequence select="'/canvas/' || encode-for-uri($pageId)" />
    </xsl:function>

    <xsl:function name="ddblabs:canvas-reference" as="map(*)">
        <xsl:param name="pageId" as="xs:string" />
        <xsl:sequence select="map {
                'id': ddblabs:append-path($itemUrl, ddblabs:canvas-path($pageId)),
                'type': 'Canvas'
            }" />
    </xsl:function>

    <!-- IIIF Image API und URL-Bildung -->

    <!-- Decoder für die skalaren und als Array gelieferten Werte von @context und profile. -->
    <xsl:function name="ddblabs:string-values" as="xs:string*">
        <xsl:param name="value" as="item()*" />
        <xsl:variable name="entries" select="if ($value instance of array(*)) then $value?* else $value" />
        <xsl:sequence select="$entries[. instance of xs:string]" />
    </xsl:function>

    <!--
        Die Image-API-Version stammt aus der Context-URI. Das Profil liefert das
        höchste angegebene Level von level0 bis level2. Alte Server verwenden hierfür
        Profil-URIs, neuere auch kurze Namen. Bei nicht abrufbaren oder unvollständigen
        Angaben bleibt das Ergebnis leer, damit der Canvas seine Rückfallwerte verwendet.
    -->
    <xsl:function name="ddblabs:read-image-info" as="map(xs:string, item()?)?">
        <xsl:param name="url" as="xs:string" />

        <xsl:try>
            <xsl:variable name="info" select="json-doc($url)" />
            <xsl:variable name="context" select="
                    ddblabs:string-values($info?('@context'))
                        [matches(., '^https?://iiif\.io/api/image/[123]/context\.json$')][1]
                " />
            <xsl:variable name="levels" select="
                    ddblabs:string-values($info?profile)[matches(., '(^|[/#])level[0-2](\.json)?$')]
                        ! replace(., '^.*(level[0-2])(\.json)?$', '$1')
                " />
            <xsl:if test="exists($context) and exists($levels)
                    and $info?width castable as xs:positiveInteger
                    and $info?height castable as xs:positiveInteger">
                <xsl:sequence select="map {
                        'version': xs:integer(replace($context, '^.*/([123])/context\.json$', '$1')),
                        'width': xs:positiveInteger($info?width),
                        'height': xs:positiveInteger($info?height),
                        'profile': sort($levels)[last()]
                    }" />
            </xsl:if>
            <xsl:catch />
        </xsl:try>
    </xsl:function>

    <!-- Die Vorschau passt in 400 × 300 Pixel, behält das Seitenverhältnis und wird nie hochskaliert. -->
    <xsl:function name="ddblabs:thumbnail-dimensions" as="map(xs:string, xs:integer)">
        <xsl:param name="width" as="xs:integer" />
        <xsl:param name="height" as="xs:integer" />

        <xsl:variable name="scale" select="min((1, 400 div $width, 300 div $height))" />
        <xsl:sequence select="map {
                'width': xs:integer(ceiling($width * $scale)),
                'height': xs:integer(ceiling($height * $scale))
            }" />
    </xsl:function>

    <!--
        Ohne Zielmaße und bei level0 wird die volle Größe angefragt. Image API 3
        verwendet dafür max, die älteren Versionen full. Verkleinerte Anfragen geben
        bei Version 3 Breite und Höhe an und sonst nur die Breite. Version 1 erwartet
        die Qualitätsangabe native, ab Version 2 gilt default.
    -->
    <xsl:function name="ddblabs:iiif-image" as="map(*)">
        <xsl:param name="serviceUrl" as="xs:string" />
        <xsl:param name="info" as="map(*)" />
        <xsl:param name="targetDimensions" as="map(*)?" />

        <xsl:variable name="fullSize" select="empty($targetDimensions) or $info?profile = 'level0'" />
        <xsl:variable name="size" select="
                if ($fullSize) then (if ($info?version = 3) then 'max' else 'full')
                else if ($info?version = 3) then $targetDimensions?width || ',' || $targetDimensions?height
                else $targetDimensions?width || ','
            " />
        <xsl:variable name="quality" select="if ($info?version = 1) then 'native' else 'default'" />
        <xsl:variable name="dimensions" select="if ($fullSize) then $info else $targetDimensions" />

        <xsl:sequence select="map {
                'id': ddblabs:append-path($serviceUrl, '/full/' || $size || '/0/' || $quality || '.jpg'),
                'type': 'Image',
                'format': 'image/jpeg',
                'width': $dimensions?width,
                'height': $dimensions?height,
                'service': [map {
                    'id': $serviceUrl,
                    'type': 'ImageService' || $info?version,
                    'profile': $info?profile
                }]
            }" />
    </xsl:function>

    <!-- Entfernt /info.json oder die Parameter einer Bildanfrage und behält die Query des Dienstes bei. -->
    <xsl:function name="ddblabs:iiif-base-url" as="xs:string">
        <xsl:param name="url" as="xs:string" />

        <xsl:variable name="path" select="replace(normalize-space(substring-before($url || '?', '?')), '/$', '')" />
        <xsl:variable name="base" select="replace($path, '/(info\.json|[^/]+/[^/]+/[^/]+/default\.\w+)$', '')" />
        <xsl:sequence select="$base || (if (contains($url, '?')) then '?' || substring-after($url, '?') else '')" />
    </xsl:function>

    <!-- Der Pfad muss vor die Query, etwa /manifest/canvas/P1?system=Q1. -->
    <xsl:function name="ddblabs:append-path" as="xs:string">
        <xsl:param name="uri" as="xs:string" />
        <xsl:param name="path" as="xs:string" />

        <xsl:sequence select="
                if (contains($uri, '?')) then substring-before($uri, '?') || $path || '?' || substring-after($uri, '?')
                else $uri || $path
            " />
    </xsl:function>

    <!-- Zuschreibungen erhalten HTML, wenn eine HTTP(S)-PURL vorliegt. Die Serialisierung maskiert Text und Attributwerte. -->
    <xsl:function name="ddblabs:generate-link" as="xs:string">
        <xsl:param name="text" as="xs:string" />
        <xsl:param name="url" as="xs:string?" />
        <xsl:param name="openInNewTab" as="xs:boolean?" />

        <xsl:variable name="href" select="normalize-space($url)" />
        <xsl:variable name="link" as="node()*">
            <xsl:choose>
                <xsl:when test="matches($href, '^https?://[^/\s]', 'i')">
                    <a href="{$href}">
                        <xsl:if test="$openInNewTab">
                            <xsl:attribute name="target">_blank</xsl:attribute>
                            <xsl:attribute name="rel">noopener noreferrer</xsl:attribute>
                        </xsl:if>
                        <xsl:value-of select="$text" />
                    </a>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:value-of select="$text" />
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        <xsl:sequence select="serialize($link, map { 'method': 'html' })" />
    </xsl:function>

</xsl:stylesheet>
