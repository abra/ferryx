/// The user-agent stylesheet for XHTML content documents: the HTML
/// standard's rendering section, trimmed to the properties the layout
/// supports. Reader themes and font settings come as a user-origin sheet
/// on top (`StyleResolver`), author sheets from the book in between.
library;

const String cssUserAgentStyleSheet = '''
html, body, address, blockquote, center, div, figure, figcaption, footer,
form, header, hr, legend, listing, main, p, plaintext, pre, xmp, search,
article, aside, h1, h2, h3, h4, h5, h6, hgroup, nav, section,
dir, dd, dl, dt, menu, ol, ul, table, caption, fieldset, details, summary,
dialog, optgroup, option { display: block; }
li { display: list-item; }
head, link, meta, script, style, title, base, template, area, param,
datalist, noembed, noframes, rp, [hidden] { display: none; }
table { display: table; }
caption { display: table-caption; }
colgroup { display: table-column-group; }
col { display: table-column; }
thead { display: table-header-group; }
tbody { display: table-row-group; }
tfoot { display: table-footer-group; }
tr { display: table-row; }
td, th { display: table-cell; }
ruby { display: ruby; }
rt { display: ruby-text; font-size: 50%; }

body { margin: 8px; }
address, blockquote, center, div, figure, figcaption, footer, form, header,
hr, legend, listing, main, p, plaintext, pre, xmp { display: block; }
blockquote, figure { margin: 1em 40px; }
p, dl, dir, menu, ol, ul, pre, listing, plaintext, xmp { margin: 1em 0; }
address { font-style: italic; }
listing, plaintext, pre, xmp { font-family: monospace; white-space: pre; }
dd { margin-left: 40px; }
dir, menu, ol, ul { padding-left: 40px; }
ol { list-style-type: decimal; }
dir dir, dir menu, dir ul, menu dir, menu menu, menu ul, ol dir, ol menu,
ol ul, ul dir, ul menu, ul ul { list-style-type: circle; margin-top: 0; margin-bottom: 0; }
dir dir dir, dir dir menu, dir dir ul, dir menu dir, dir menu menu,
dir menu ul, dir ul dir, dir ul menu, dir ul ul, menu dir dir, menu dir menu,
menu dir ul, menu menu dir, menu menu menu, menu menu ul, menu ul dir,
menu ul menu, menu ul ul, ol dir dir, ol dir menu, ol dir ul, ol menu dir,
ol menu menu, ol menu ul, ol ul dir, ol ul menu, ol ul ul, ul dir dir,
ul dir menu, ul dir ul, ul menu dir, ul menu menu, ul menu ul, ul ul dir,
ul ul menu, ul ul ul { list-style-type: square; }
center { text-align: center; }

cite, dfn, em, i, var { font-style: italic; }
b, strong { font-weight: bold; }
code, kbd, samp, tt { font-family: monospace; }
big { font-size: larger; }
small { font-size: smaller; }
sub { vertical-align: sub; }
sup { vertical-align: super; }
sub, sup { font-size: smaller; line-height: normal; }
ruby > rt { font-size: 50%; }
:link, a[href] { color: #0000EE; text-decoration: underline; }
:visited { color: #551A8B; }
mark { background-color: yellow; color: black; }
abbr[title], acronym[title] { text-decoration: underline; }
ins, u { text-decoration: underline; }
del, s, strike { text-decoration: line-through; }
q::before { content: open-quote; }
q::after { content: close-quote; }
math[display="block" i] { display: block; text-align: center; margin: 1em 0; }

h1 { font-size: 2.00em; font-weight: bold; margin: 0.67em 0; }
h2 { font-size: 1.50em; font-weight: bold; margin: 0.83em 0; }
h3 { font-size: 1.17em; font-weight: bold; margin: 1.00em 0; }
h4 { font-size: 1.00em; font-weight: bold; margin: 1.33em 0; }
h5 { font-size: 0.83em; font-weight: bold; margin: 1.67em 0; }
h6 { font-size: 0.67em; font-weight: bold; margin: 2.33em 0; }
article h1, aside h1, nav h1, section h1 { font-size: 1.50em; margin: 0.83em 0; }

table { box-sizing: border-box; border-spacing: 2px; border-collapse: separate; text-indent: initial; }
table { border-color: gray; }
thead, tbody, tfoot, table > tr { vertical-align: middle; }
tr, td, th { vertical-align: inherit; }
th { font-weight: bold; text-align: center; }
caption { text-align: center; }
td, th { padding: 1px; }
table[border] { border-style: outset; }
table[border] > tr > td, table[border] > tr > th,
table[border] > thead > tr > td, table[border] > thead > tr > th,
table[border] > tbody > tr > td, table[border] > tbody > tr > th,
table[border] > tfoot > tr > td, table[border] > tfoot > tr > th { border-style: inset; }

hr { color: gray; border-style: inset; border-width: 1px; margin: 0.5em auto; }
fieldset { margin-left: 2px; margin-right: 2px; border: 2px groove; padding: 0.35em 0.75em 0.625em; }
legend { padding-left: 2px; padding-right: 2px; }
img, video, canvas { vertical-align: baseline; }
[dir=ltr i] { direction: ltr; }
[dir=rtl i] { direction: rtl; }
bdi, output, [dir=ltr i], [dir=rtl i] { unicode-bidi: isolate; }
bdo { unicode-bidi: bidi-override; }
nobr { white-space: nowrap; }
''';
