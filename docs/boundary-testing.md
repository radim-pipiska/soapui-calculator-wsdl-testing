# Testovací sada dat pro POST /payments a Kalkulačku

## 1. Testovací sada: POST /payments /AI
Fiktivní specifikace: amount je 0,01 až 10000,00 včetně, currency je povinná (CZK, EUR). Specifikace nic neříká o více než dvou desetinných místech ani o záporné hodnotě.

| Hodnota | Co testuje (třída/hranice) | Platná? | Zdroj platnosti | Zbývá otázka / Poznámka |
| :--- | :--- | :--- | :--- | :--- |
| **8642.64** | Třída (Validní vnitřní) | Ano | Specifikace | V pořádku. |
| **10000.00** | Hranice (Max platná) | Ano | Specifikace | V pořádku. |
| **0.01** | Hranice (Min platná) | Ano | Specifikace | V pořádku. |
| **9999.99** | Hranice (BVA interní) | Ano | Návrh (BVA) | Odvozeno z předpokladu 2 desetinných míst. |
| **0.02** | Hranice (BVA interní) | Ano | Návrh (BVA) | Odvozeno z předpokladu 2 desetinných míst. |
| **10000.01** | Hranice (Max neplatná) | Ne | Návrh (BVA) | Jak přesně systém vrátí chybu? (HTTP 400? Validace v JSON?) |
| **0.00** | Hranice (Min neplatná) | Ne | Návrh (BVA) | Akceptuje systém čistou nulu? Jaká bude chybová hláška? |
| **0** | Třída (Formát - Integer) | Ne | Domněnka | Převede se interně na `0.00`? Je validní poslat číslo bez desetinné tečky? |
| **100** | Třída (Formát - Integer) | Ano | Domněnka | **Otázka na PO/Dev:** Dovoluje API posílat celá čísla, nebo striktně vyžaduje float (např. `100.00`)? |
| **null** | Třída (Prázdná hodnota) | Ne | Domněnka | Jak systém odpoví na `null`? Spadne s NullPointerException (500), nebo vrátí 400? |
| **Chybějící pole** | Třída (Struktura JSON) | Ne | Domněnka | Je `amount` povinný parametr? Pokud chybí, jaká je chybová odpověď? |
| **0.0123** | Hranice (Přesnost čísla) | Ne | Domněnka | **Kritická otázka:** Ořízne systém hodnotu na `0.01` (bude platná), zaokrouhlí ji, nebo platbu odmítne? |
| **-0.01** | Hranice (Záporná hodnota) | Ne | Domněnka | **Otázka na Dev:** Je v kódu validace na záporná čísla? Nezkonvertuje se interně na `0.01`? |
| **100,50** | Třída (Neplatný znak) | Ne | Domněnka | JSON formát čárku v čísle nedovoluje (bude to brát jako nevalidní JSON). Vrátí parser HTTP 400? |
| **třitisíce...** | Třída (Jiný datový typ) | Ne | Domněnka | String místo čísla. Ošetří to vestavěný framework, nebo to proteče do aplikace? |
| **999999999** | Třída (Extrémní hodnota) | Ne | Návrh (Robustnost) | Test na přetečení datového typu (Overflow). |

## 2. Testovací sada: Mapování na Calculator (Integer hranice) /AI
Tato tabulka mapuje technické chování aplikace na úrovni 32-bitového Integeru (`int`), kde dochází k ošetření přetečení (overflow) a kontrole struktury vstupu.

| Hodnota / Vstup | Co testuje (třída/hranice) | Platná? | Zdroj platnosti | Zbývá otázka / Poznámka |
| :--- | :--- | :--- | :--- | :--- |
| **2147483646 + 1** | Hranice (Max platná pro 32-bit int) | Ano | Technická specifikace | Výsledná hodnota `2147483647` je maximální kladné číslo pro podepsaný 32-bit integer. |
| **2147483647 + 1** | Hranice (Max neplatná - Overflow) | Ne | Návrh (Robustnost) | **Kritický test:** Dojde k přetečení do záporných čísel (`-2147483648`), nebo kalkulačka vyhodí bezpečnou výjimku? |
| **Prázdný intB** | Třída (Tvar vstupu / Neúplná struktura) | Ne | Domněnka | **Otázka na Dev:** Pokud chybí druhý operant (intB), jak kalkulačka zareaguje? Dosadí defaultní nulu, nebo vrátí chybu validace vstupu? |
