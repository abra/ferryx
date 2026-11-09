// Regenerates icu_sentence_breaks.json: sentence boundaries from
// Intl.Segmenter (ICU), the WebView reader's source of truth, for curated
// text and random strings over characters of every sentence-break class.
// Run: node test/fixtures/icu_sentence_breaks.mjs test/fixtures/icu_sentence_breaks.json
import { writeFileSync } from 'node:fs'
const seg = new Intl.Segmenter('en', { granularity: 'sentence' })
const breaks = s => { const b = [...seg.segment(s)].map(x => x.index); b.push(s.length); return b }
const curated = [
  'Mr. Smith went. "Yes!" he said... (Really?) 3.14 is pi. e.g. this. ok',
  'Hello world. How are you? I am fine! Thanks.',
  'He said "Stop." Then he left.',
  'U.S.A. is big. The U.S. Army.',
  'Это первое предложение. А это второе! Правда? да.',
  '日本語の文。次の文！最後の文？',
  'One;\ttwo.  Three\nFour.\r\nFive Six',
  'Wait… what? Okay.',
  'Ends with spaces.   ',
  '(Parenthetical.) Next one.',
  'Number 1. 2. 3. Go.',
  'Café. Naïve. été. Done.',
  'Emoji 👍. Family 👨‍👩‍👧. End.',
  '«Привет», — сказал он. «Пока!» — ответила она.',
  'a.b.c. D.E. f',
  'No terminator at all',
  '¿Qué? ¡Sí! Bien.',
  'Soft­hyphen. Next.',
  'NBSP. Next. Tab.\tNext.',
  'Armenian։ Next. Arabic؟ Next.',
  'Is it 5.5? Yes. 5. Five.',
  '"Quote." \'Single.\' ‘Curly.’ “Double.” Next',
  'semi; colon: dash - en – em — comma, ok. Next',
  'x.​Y. z.⁠W.',
]
const pool = ['a','b','A','B','.','?','!',' ',' ','\n','\r','"',')','(',',','1','2','é','‍','­','。','д','Д',' ','«','»',';',':','-',' ','\t','日','…','’',"'",'։','̀','x','Y','.']
let seed = 42
const rand = n => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed % n }
const fuzz = []
for (let i = 0; i < 1500; i++) {
  let s = ''
  const len = 1 + rand(12)
  for (let j = 0; j < len; j++) s += pool[rand(pool.length)]
  fuzz.push(s)
}
const cases = [...curated, ...fuzz].map(text => ({ text, breaks: breaks(text) }))
writeFileSync(process.argv[2], JSON.stringify({ icu: process.versions.icu, unicode: process.versions.unicode, cases }))
console.log('icu', process.versions.icu, 'unicode', process.versions.unicode, cases.length)
