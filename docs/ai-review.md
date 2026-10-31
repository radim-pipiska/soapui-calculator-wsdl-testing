# Kontrola výstupů AI při psaní asercí (SoapUI, Calculator)

Nástroj: SoapUI 5.10.0. Služba: veřejná demo služba třetí strany `http://www.dneonline.com/calculator.asmx`.
Ověřováno v říjnu 2026.

## Princip

AI beru jako pomocníka při návrhu asercí, ne jako zdroj ověřených faktů. Rozhodující je až **skutečný běh testu** a porovnání výsledku s logem SoapUI.

## Postup

1. Připravím prompt z ověřených podkladů: **skutečné SOAP odpovědi, správné adresy a namespace**. Použité verze promptů ukládám do složky `prompts/`.
2. Návrhy AI rozdělím na jednotlivá tvrzení a každé samostatně prověřím v SoapUI.
3. Nejdřív ověřím, že aserce prochází nad správnou odpovědí. Potom změním vždy jen jednu hodnotu nebo část vstupu a sleduji, zda aserce správně selže.
4. Výsledek porovnám s logem. Nepotvrzené závěry označím jako neověřené a chybné zapíšu jako zjištění.

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
Při hledání příčiny nestačí odhad ani jednorázový zelený výsledek. I vlastní hypotézy musím ověřovat pozitivní kontrolou a měnit vždy jen jednu věc. Zároveň si hlídám, zda pracuji se správnou odpovědí a zda mám výsledek doložený logem nebo screenshotem. Zelená aserce před změnou a její očekávané selhání po změně jsou důležité, ale samy o sobě nepotvrzují správnost celé testovací sady.

## Otevřené

- Příčina selhání wildcardu na uzlu `faultstring` (podezření: nový řádek) `[DOPLNIT po úloze 18]`
