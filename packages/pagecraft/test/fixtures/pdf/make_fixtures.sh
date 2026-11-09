#!/bin/sh
# Regenerates the PDF fixtures from their PostScript sources with Ghostscript.
# Run from this directory; commit the resulting PDFs.
set -e
GS="gs -q -dBATCH -dNOPAUSE -sDEVICE=pdfwrite"
$GS -sOutputFile=text_outline.pdf text_outline.ps
$GS -sOutputFile=plain.pdf plain.ps
# User password "secret", owner password "owner" (RC4 128-bit, R3).
$GS -sOwnerPassword=owner -sUserPassword=secret -sOutputFile=locked.pdf text_outline.ps
$GS -sOutputFile=many_pages.pdf many_pages.ps
$GS -sOutputFile=text_lines.pdf text_lines.ps
$GS -sOutputFile=figure.pdf figure.ps
