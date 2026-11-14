# Testovací sada dat pro POST /payments a Calculator

## 1. Testovací sada: POST /payments
Fiktivní specifikace: amount je 0,01 až 10000,00 včetně. Záporné hodnoty plynou z rozsahu, spec neříká, jak se odmítnou. Spec také nic neříká o více než dvou desetinných místech.

| hodnota | co testuje (třída/hranice) | platná? | zdroj platnosti | Otázka na analytika |
| :--- | :--- | :--- | :--- | :--- |
| 8642.64 | třída | ano | specifikace | |
| 10000.00 | hranice | ano | specifikace | platí maximum 10000 stejně pro CZK i EUR? |
| 0.01 | hranice | ano | specifikace| |
| 9999.99 | hranice | ano | specifikace | |
| 0.02 | hranice | ano | specifikace | |
| 10000.01 | hranice | ne | specifikace | |
| 0.00 | hranice | ne | specifikace | co se stane při hodnotě 0.00? |
| 100 | třída | nejasné | otázka na analytika | doplní dvě desetinná místa? |
| null | třída | ne | domněnka | co se stane s prázdnou hodnotou |
| chybějící pole | třída | nejasné | otázka na analytika | je parametr amount povinný? |
| 0.0123 | hranice | nejasné | otázka na analytika | zaokrouhlení, oříznutí, odmítnutí? |
| -0.01 | záporná hodnota | ne | specifikace | co se stane se zápornou hodnotou menší než 0.00? |
| 100,50 | třída | ne | domněnka | desetinná čárka místo tečky, co se stane? |
| třitisícestodvacetdvě | třída | ne | domněnka | jiný datový typ, co se stane? |

**Jaký status kód a tělo chyby vrací odmítnutý 'amount'?**

## 2. Testovací sada: Mapování na Calculator (Integer hranice) /AI
Tato tabulka mapuje technické chování aplikace na úrovni 32-bitového Integeru (`int`), kde dochází k ošetření přetečení (overflow) a kontrole struktury vstupu.

| Hodnota / Vstup | Co testuje (třída/hranice) | Platná? | Zdroj platnosti | Skutečný výsledek (Pozorování z notes.md) |
| :--- | :--- | :--- | :--- | :--- |
| **2147483646 + 1** | Hranice (Max platná pro 32-bit int) | Ano | WSDL (XSD, s:int) | Výsledná hodnota je `2147483647` (maximální kladné číslo pro podepsaný 32-bit integer). |
| **2147483647 + 1** | Hranice (Max neplatná - Overflow) | Ne | Výsledek mimo rozsah s:int (WSDL) | **HTTP 500, Fault soap:Server, OverflowException**. Nedochází k přetečení do záporných čísel. |
| **Prázdný intB** | Třída (Tvar vstupu / Neúplná struktura) | Ne | WSDL (XSD, s:int); Divide (SOAP 1.1) | **Fault soap:Client**. Služba nedosazuje defaultní nulu [HYPOTÉZA] (k tomu docházelo pouze při chybě v namespace). |

