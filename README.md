# SoapUI: testování SOAP služby Calculator (WSDL, XML, XPath, řetězení kroků)

Učební projekt (říjen 2026): testování SOAP API v **SoapUI 5.10.0** na veřejné demo službě třetí strany `http://www.dneonline.com/calculator.asmx?WSDL`. Nejsem autor ani provozovatel služby. Specifikace chování neexistuje, proto jsou závěry označeny jako **pozorování**, ne jako potvrzené vady.

## Obsah repozitáře

- `soapui/Calculator-soapui-project.xml` export projektu SoapUI (bez hesel a tajných hodnot)
- `notes.md` pozorování, experimenty a doslovné hlášky
- `docs/ai-review.md` kontrola výstupů AI (tvrzení, ověření, verdikt)
- `prompts/` verze promptů pro AI a jejich výstupy
- `screenshots/` důkazy k experimentům

## Co projekt obsahuje

Projekt `Calculator` má dvě rozhraní (`CalculatorSoap` = SOAP 1.1, `CalculatorSoap12` = SOAP 1.2) a TestSuite `Calculator` se třemi TestCase:

| TestCase | Obsah |
|---|---|
| `Add funkce` | Add (7 + 5 = 12), hranice typu `int` (2147483646 + 1 platné, 2147483647 + 1 Fault) `[OVĚŘIT obsah proti projektu]` |
| `Divide funkce` | happy path (2 / 2 = 1) a dělení nulou (2 / 0, SOAP Fault) |
| `Chain` | Add, Property Transfer, Add: přenos výsledku prvního kroku do druhého |

Použité aserce: SOAP Response, Schema Compliance, XPath Match, Valid HTTP Status Codes, SOAP Fault / Not SOAP Fault, Contains.

## Hlavní zjištění (pozorování)

1. XPath `//AddResult` bez deklarace namespace nenajde nic, i když element v odpovědi je. Je nutné deklarovat `http://tempuri.org/`.
2. Request s chybným namespace (`tempura`) vrátil `AddResult` = `0` bez Faultu. Aserce SOAP Response a Schema Compliance zůstaly zelené, chybu zachytila až aserce na hodnotu (rozhraní SOAP 1.1).
3. Dělení nulou (2 / 0, také 0 / 0): HTTP 500, Fault `soap:Server` s `System.OverflowException` a cestou k souboru na serveru. Specifikace chybí, proto jde o pozorování.
4. 2147483646 + 1 vrátí 2147483647, 2147483647 + 1 vrátí Fault s `OverflowException`.
5. 7 / 2 vrátí 4 (ne 3): služba nedělí celá čísla s oříznutím. Mechanismus neznám.
6. Property Transfer: s volbou *Set null on missing source* hlásí přenos OK a pošle prázdný `intA`, server vrátí Fault. Bez ní přenos selže hned (`Missing match for Source XPath`). Přenesená hodnota zůstává v requestu i po běhu.
7. Wildcard v XPath Match fungoval na `faultcode` (`soap:*`), ale ne na `faultstring`. Příčina neznámá, aserce je řešena funkcí `contains()`.

## Pracovní postup

- Očekávané hodnoty počítám ze vstupů, ne z odpovědi služby.
- U každé aserce nejdřív ověřím zelený stav, pak provedu sabotáž (změna hodnoty, namespace nebo vstupu) a zapíšu doslovnou hlášku.
- Výstupy AI ověřuji spuštěním, viz `docs/ai-review.md`.

## Jak spustit

1. SoapUI 5.10.0: *File → Import Project* a vyber `soapui/Calculator-soapui-project.xml`.
2. TestSuite `Calculator`: pravý klik → *Run*.
3. Služba je třetí strany a může se změnit nebo být nedostupná. Výsledky pak nemusí odpovídat.

## Stav

Rozpracováno. Poslední ověřený zelený běh: `[DOPLNIT RUČNĚ: datum]`. Otevřené body jsou na konci `notes.md`.

## Licence

`[DOPLNIT RUČNĚ: licence]`
