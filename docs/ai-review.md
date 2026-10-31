<!-- KONCEPT: před zveřejněním přepsat vlastními slovy, projít každý řádek proti vlastním logům a smazat tento řádek -->
# Kontrola výstupů AI při psaní asercí (SoapUI, Calculator)

Nástroj: SoapUI 5.10.0. Služba: veřejná demo služba třetí strany `http://www.dneonline.com/calculator.asmx`.
Ověřováno v říjnu 2026.

## Princip

AI mi navrhuje aserce, ale **nic nedokazuje**. Důkaz je běh v SoapUI a doslovné srovnání s logem. U každého tvrzení AI proto zapisuji, jak jsem ho ověřil a co vyšlo.

## Postup

1. Do promptu dávám skutečnou odpověď zkopírovanou z karty Raw, správnou adresu služby a přesné URI namespace. Moje první verze promptů měly chyby (useknuté URI `http://w3.org`, špatná adresa, odpověď z jiné operace, než popisoval scénář), proto prompty verzuji ve složce `prompts/`.
2. Výstup AI rozdělím na jednotlivá tvrzení.
3. Každé tvrzení ověřím spuštěním a porovnám s logem (doslovné hlášky, chování funkcí).
4. U každé aserce ověřím zelený stav **před** sabotáží. Aserce, která byla červená už na začátku, nic nedokazuje.
5. Sabotáž provedu změnou očekávané hodnoty, namespace nebo vstupu a zapíšu doslovnou hlášku. Při sabotáži měním vždy jen jednu věc.
6. Neověřené tvrzení nemažu, ale označím ho jako neověřené. Vyvrácené tvrzení zapíšu jako zjištění.

## Ověřená tvrzení (prompt CZ v6, výstupy CZ a EN)

| # | Tvrzení AI | Jak ověřeno | Verdikt |
|---|---|---|---|
| 1 | XPath na `faultcode`: `//soap:Envelope/soap:Body/soap:Fault/faultcode` s namespace `http://schemas.xmlsoap.org/soap/envelope/`, `faultcode` bez prefixu | Aserce s touto cestou je zelená na Divide 2 / 0 (Expected `soap:*`). Sabotáž hodnoty (Expected `xsoap:*`) dala `expecting [xsoap:*], actual was [soap:Server]` | Správně |
| 2 | Při selhání na platném vstupu (2 / 2) hlásí SoapUI `XPath contains no matches` (výstup CZ) | Skutečná hláška: `Exception:Missing content for xpath [...] in Response` | Vymyšleno (výstup EN hlášku uvedl správně) |
| 3 | Platná odpověď obsahuje `DivideResult` a HTTP 200 | 2 / 2 vrací HTTP 200 a `<DivideResult>1</DivideResult>` | Správně, ale AI to neoznačila jako předpoklad |
| 4 | Test platným vstupem `4 / 2` (výstup CZ) | Prompt žádal `2 / 2` | Odchylka od zadání |
| 5 | Aserce na `faultstring` s hvězdičkami (`*Server was unable to process request.*System.OverflowException: Arithmetic operation resulted in an overflow.*`, Allow Wildcards zaškrtnuto) projde | Aserce byla červená už ve výchozím stavu na Divide 2 / 0 | Nefunguje |
| 6 | Prostřední hvězdička pohltí konce řádků (výstup CZ) | Nový řádek je v textu až za `overflow.`, mezi `request.` a `System` je jen ` ---> `. Po `normalize-space` selhaly i `System*`, `*unable*`, `*System.OverflowException*` a další výrazy. Pokusy s `normalize-space` jsou ale neplatné: wildcard na výsledku funkce nefunguje vůbec (`soap:*` na `normalize-space(//soap:Fault/faultcode)` je červené, uzlová verze zelená) | Vysvětlení AI je chybné. Hypotéza o novém řádku na uzlu `faultstring` zůstává neověřená, příčina neznámá |
| 7 | „Stoprocentní jistota“ po provedení sabotáže | Sabotáž ukazuje, že aserce umí selhat, ne že je celá sada správná | Přehnané tvrzení |

## Co jsem ověřil, že funguje

- Wildcard na jednořádkové hodnotě uzlu: `faultcode` s Expected `soap:*` je zelený. Na výsledku funkce (`normalize-space(...)`) wildcard nefunguje.
- Varianta bez wildcardů: XPath `contains(normalize-space(//soap:Fault/faultstring), 'System.OverflowException')` s Expected `true` je zelená. Sabotáž (`System.DivideByZeroException`) dala `expecting [true], actual was [false]`. Funkce vrací jen `true` nebo `false`: na vstupu 2 / 2 (bez Faultu) hlásí totéž `expecting [true], actual was [false]`, takže chybějící element vypadá stejně jako chybějící text (uzlová aserce by hlásila `Missing content`).
- Náhradní řešení: aserce **Contains** s obsahem `System.OverflowException`. Sabotáž `System.DivideByZeroException` dala `Missing token [System.DivideByZeroException] in Response`. Contains je slabší než XPath Match, protože hledá v celé odpovědi, ne v jednom elementu.
- Valid HTTP Status Codes (500) a SOAP Fault neodliší chybu klienta od chyby serveru: prázdný `intB` vrátí `soap:Client` s HTTP 500 a obě aserce zůstanou zelené. Spadne až `faultcode` a `faultstring`. Proto sada aserací nestojí na jedné aserci.

## Poučení z vlastních chyb

- Nejdřív jsem sám vysvětloval selhání wildcardu „novým řádkem“. Pokus to ověřit (`normalize-space`) byl nepoužitelný: wildcard na výsledku funkce nefunguje vůbec. Při hledání příčiny měním vždy jen jednu věc a nejdřív pozitivní kontrolou ověřím, že nástroj dělá to, co od něj čekám. Moje vlastní tvrzení „obě zelené“ bez screenshotu se při opakování ukázalo jako nepravdivé: výsledek bez důkazu nezapisuji jako fakt. Pravidlo „tvrzení o chování označit jako hypotézu“ platí i pro mé vlastní závěry, ne jen pro AI.
- Přesná kopie neznamená správný zdroj: do promptu jsem jednou vložil přesně zkopírovanou odpověď, ale z jiné operace.
- Zelená před sabotáží, červená až po ní, a vždy přečíst důvod červené (neshoda hodnoty, chybějící obsah, rozbitý výraz).

## Otevřené

- Příčina selhání wildcardu na uzlu `faultstring` (podezření: nový řádek) `[DOPLNIT po úloze 18]`
