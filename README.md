# SoapUI: testování SOAP služby Calculator (WSDL, XML, XPath)

Učební projekt: základy testování SOAP API v SoapUI na veřejné demo službě třetí strany.
Služba: `http://www.dneonline.com/calculator.asmx?WSDL` (nejsem její autor ani provozovatel).

## Co projekt ukazuje

- import WSDL a generování sample requestů
- struktura SOAP zprávy (Envelope, Header, Body) a SOAP Fault
- aserce: SOAP Response, Schema Compliance, XPath Match
- práce s namespace v XPath (deklarace vs. `local-name()`)
- sabotážní kontrola: ověření, že aserce umí selhat
- kritická kontrola výstupu AI

## Obsah

- `soapui/` export projektu ze SoapUI (XML) `Calculator-soapui-project.xml`
- `notes.md` pozorování, experimenty a závěry
- `screenshots/` důkazy k experimentům

## Hlavní zjištění

1. `//AddResult` bez deklarace namespace nenajde nic, i když element v odpovědi je.
2. Změna namespace v requestu vedla k odpovědi `0` bez chyby. Zelené aserce na strukturu proto nestačí, je potřeba aserce na hodnotu.
3. Divide s nulou vrací HTTP 500 a Fault s vnitřní výjimkou a cestou na serveru (pozorování, ne potvrzená vada).

## Stav

Rozpracováno. Otevřené body jsou na konci `notes.md`.

## Licence

## Licence

Tento projekt je open-source a je licencován pod **MIT licencí**. 

Copyright (c) 2026 Radimp

Povoluje se bezplatné používání, kopírování, modifikace a distribuce tohoto testovacího projektu pro jakékoli účely, bez jakýchkoli omezení. Projekt je poskytován "jak stojí a leží", bez jakékoli záruky.

