# Test fonts

`NotoSans-Ascii.ttf` and `NotoSans-Ascii.woff` are printable-ASCII subsets of
the app's `NotoSans-Phonetics.ttf` (Noto Sans, SIL Open Font License,
`OFL-NotoSans.txt`), for embedded-font tests: one plain sfnt, one WOFF 1.0 of
the same font. Copyright metadata is retained.

Reproduce from `packages/pagecraft/test/fixtures/fonts` with fontTools:

```sh
python3 -m fontTools.subset ../../../../component_library/fonts/NotoSans-Phonetics.ttf \
  --unicodes=U+0020-007E --output-file=NotoSans-Ascii.ttf \
  --layout-features='*' --name-IDs='*' --name-languages='*'
python3 -m fontTools.subset ../../../../component_library/fonts/NotoSans-Phonetics.ttf \
  --unicodes=U+0020-007E --output-file=NotoSans-Ascii.woff --flavor=woff \
  --layout-features='*' --name-IDs='*' --name-languages='*'
```

SHA-256:

```text
276cf03688d0797fa6e706bb3143862c5bbc65ad3e855c640cb5298f1d685fc9  NotoSans-Ascii.ttf
3573fb18dbebb5f6b401b535f117750b367c691ec12afca7c109912349f6a798  NotoSans-Ascii.woff
```
