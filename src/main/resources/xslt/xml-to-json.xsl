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
<xsl:transform expand-text="yes" version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <!--
        Zweiter Schritt der Cortex-Transformation. cortex-to-iiif.xsl liefert ein IIIF-Manifest
        in der standardisierten XML-Darstellung für JSON. xml-to-json übernimmt die JSON-Kodierung
        von Schlüsseln und Werten. Die Textserialisierung schreibt das Manifest als UTF-8.
    -->
    <xsl:output encoding="UTF-8" method="text" />
    <xsl:template match="/">
        <xsl:value-of select="xml-to-json(.)" />
    </xsl:template>
</xsl:transform>
