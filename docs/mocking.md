# Integrační testování: Návrh odpovědí mocku platební služby

Tento dokument obsahuje revidovaný návrh chování mock serveru pro fiktivní platební službu (endpoint `POST /payments`) a definici očekávaného chování objednávkového systému. Dokument slouží jako podklad pro diskuzi s analytikem a obsahuje technický návod k implementaci v nástroji Postman.

## Souhrnná tabulka testovacích scénářů (Návrh pro analytika)

*Poznámka autora: Všechna očekávání od objednávkového systému jsou v této fázi považována za kvalifikované předpoklady a náměty k diskuzi. Ve fiktivní specifikaci se nenacházejí.*

| Odpověď mocku | Co se očekává od objednávky (Návrh do diskuze) | Zdroj / Typ informace |
| :--- | :--- | :--- |
| **200 OK** + `{"status":"PAID"}` | Systém by měl objednávku přepnout do stavu „Zaplaceno“ a spustit proces expedice. | **Specifikace** (pro HTTP/JSON) / **Předpoklad autora** (pro workflow) |
| **402 Payment Required** + `{"status":"DECLINED"}` | Systém by měl objednávku ponechat v rozpracovaném stavu, uživateli zobrazit chybovou hlášku a nabídnout změnu karty. **[OTÁZKA NA ANALYTIKA: Chceme objednávku po X neúspěšných pokusech stornovat automaticky?]** | **Specifikace** (pro HTTP/JSON) / **Otázka na analytika** (pro workflow a textaci) |
| **500 Internal Server Error** | Systém by měl chybu zalogovat do monitoringu, uživateli zobrazit obecné varování a zachovat stav objednávky. **[OTÁZKA NA ANALYTIKA: Budeme implementovat automatický retry mechanismus na pozadí?]** | **Předpoklad** (simulace chybového stavu) / **Otázka na analytika** |
| **Skutečný Timeout** (Zpoždění brány) | Systém nesmí objednávku stornovat. Měl by ji interně označit jako „Ověřování“ a spustit asynchronní reconciliation proces. **[OTÁZKA NA ANALYTIKA: Existuje GET endpoint na ověření stavu visící platby?]** | **Předpoklad** (simulace sítě) / **Otázka na analytika** |
| **200 OK** + prázdné tělo | Systém musí bezpečně ošetřit selhání parsování (nesmí spadnout), transakci neuznat a zalogovat kritickou chybu. **[OTÁZKA NA ANALYTIKA: Jak komunikovat nevalidní data brány koncovému klientovi?]** | **Předpoklad** (detekce nekonzistence) / **Otázka na analytika** |

---

## Technická implementace v Postmanu

Celá konfigurace mocku je navržena tak, aby byla plně přenositelná v rámci jednoho JSON souboru kolekce. Veškerá stavová logika je uložena v proměnných kolekce (**Collection Variables**).

### Architektura kolekce
Aby se zamezilo nechtěnému chování a duplicitám při párování příkladů, je kolekce rozdělena na definici dat a samotné exekutorské požadavky:

1. **`[Definice brány] POST /payments`** – Tento požadavek slouží pouze jako úložiště pro mock server. Obsahuje přesně 5 unikátních příkladů (Examples): `Scenario_PAID`, `Scenario_DECLINED`, `Scenario_500`, `Scenario_Empty` a `Scenario_Timeout`.
2. **`Zpracovat platbu (Sequential)`** – Testovací požadavek pro deterministické testování. Postupně střídá stavy od indexu 0.
3. **`Zpracovat platbu (Randomized)`** – Testovací požadavek pro průzkumné testování robustnosti. *Upozornění: Tento režim je nevhodný pro regresní testování, protože odlišný běh generuje různé pokrytí kódu.*

### Správa proměnných (Důležité pro import)
Aby byla kolekce funkční ihned po importu, hodnoty musí být striktně zapsány v polích **Initial Value**. Pokud by byly vyplněny pouze v *Current Value*, exportovaný JSON bude prázdný a Pre-request skript selže v Runneru s chybou `SyntaxError` (nikoliv chybou testu Failed), protože metoda `JSON.parse()` nedokáže zpracovat prázdný řetězec.

V tabulce proměnných kolekce nastavte:
* `scenarios` (Initial Value): `["Scenario_PAID", "Scenario_DECLINED", "Scenario_500", "Scenario_Empty", "Scenario_Timeout"]`
* `sequential_index` (Initial Value): `0`
* `mock_url` (Initial Value): *Čistá doména vašeho mocku bez protokolu `https://` (např. `vaše-id.mock.pstmn.io`). Protokol je pevně předřazen v samotném URL požadavku.*

---

## Skripty a simulace negativních stavů /AI

### Pre-request Script pro `Zpracovat platbu (Sequential)`
```javascript
// 1. Načteme pole scénářů z proměnných kolekce
let scenarios = JSON.parse(pm.collectionVariables.get("scenarios"));

// === KONTROLA PRO RUNNER ===
// Pokud spouštíme Runner a jsme v úplně první iteraci,
// vynutíme reset sekvenčního indexu na 0, aby testy začaly vždy od PAID
if (pm.info.iteration === 0) {
    pm.collectionVariables.set("sequential_index", 0);
}
// ===================================

// 2. Načteme izolovaný index pro sekvenční volání
let currentIndex = parseInt(pm.collectionVariables.get("sequential_index"));

if (isNaN(currentIndex)) {
    currentIndex = 0;
}

// 3. Vybereme scénář
let currentScenario = scenarios[currentIndex];

// 4. Uložíme ho do proměnné pro hlavičku a pro Test skript
pm.collectionVariables.set("next_scenario", currentScenario);

// Simulace reálného timeoutu (zpoždění na straně mock serveru)
if (currentScenario === "Scenario_Timeout") {
    // Využití oficiální hlavičky Postman mocku pro umělé zpoždění odpovědi v ms
    pm.request.headers.add({ key: "x-mock-response-delay", value: "10000" });
    console.log("-> [SEQUENTIAL] Aktivována simulace timeoutu (delay 10s)");
} else {
    // Pro ostatní scénáře vynutíme okamžitou odpověď (0ms)
    pm.request.headers.add({ key: "x-mock-response-delay", value: "0" });
}

console.log("-> [SEQUENTIAL] Vybrána odpověď: " + currentScenario);

// 5. Vypočítáme další index v pořadí a uložíme ho zpět do sequential_index
let nextIndex = (currentIndex + 1) % scenarios.length;
pm.collectionVariables.set("sequential_index", nextIndex);
```

### Pre-request Script pro `Zpracovat platbu (Randomized)`
```javascript
let scenarios = JSON.parse(pm.collectionVariables.get("scenarios"));
let randomIndex = Math.floor(Math.random() * scenarios.length);
let currentScenario = scenarios[randomIndex];

pm.collectionVariables.set("next_scenario", currentScenario);

if (currentScenario === "Scenario_Timeout") {
    pm.request.headers.add({ key: "x-mock-response-delay", value: "10000" });
} else {
    pm.request.headers.add({ key: "x-mock-response-delay", value: "0" });
}

pm.request.headers.add({ key: "x-mock-response-name", value: currentScenario });
console.log("-> [RANDOMIZED] Vybrána náhodná odpověď: " + currentScenario);
```

---

## Ověření a doložení chybového stavu (Smoke test mocku)

Následující kód se vkládá do záložky **Tests** u obou exekutorských požadavků. Slouží výhradně jako **smoke test funkčnosti samotného mocku** (ověřuje, že Postman vybral správný příklad). Nedokáže ověřit chování externího objednávkového systému.

**Smoke test skript/AI:**
```javascript
let activeScenario = pm.collectionVariables.get("next_scenario");

let expectedStatuses = {
    "Scenario_PAID": 200,
    "Scenario_DECLINED": 402,
    "Scenario_500": 500,
    "Scenario_Empty": 200,
    "Scenario_Timeout": 200
};
let expectedStatusCode = expectedStatuses[activeScenario];

pm.test(`[SMOKE TEST MOCKU] - ${activeScenario} vrací kód ${expectedStatusCode}`, function () {
    pm.response.to.have.status(expectedStatusCode);
});
```

### Doložení sabotáže (Ověření, že test umí selhat)
Aby bylo prokazatelné, že testy pouze pasivně neprocházejí, byl proveden test sabotáže:
1. U uloženého příkladu `Scenario_DECLINED` byl záměrně změněn návratový status kód v pravém horním rohu z `402 Payment Required` na `200 OK`.
2. Při spuštění sekvenčního testu testovací aserce selhala a vygenerovala korektní červenou [chybovou hlášku](../screenshots/Scenario_DECLINED_Sabotage.png):
   `AssertionError: expected response to have status code 402 but got 200`

---

## Bezpečnost a metadata při exportu
Při exportu kolekce vygeneruje Postman v JSON struktuře pole `_exporter_id`. Toto ID reprezentuje pouze interní číslo účtu workspace v cloudu Postmanu. Bylo vědomě rozhodnuto toto ID v souboru ponechat, protože neobsahuje žádné tajné klíče, hesla ani osobní údaje a je bezpečné pro uložení do veřejného repozitáře na GitHubu.

---

## Odkazy a zdroje
* Pravidla pro neomezené využití mocků: [Postman Docs - About plans](https://learning.postman.com/latest-v-12/docs/billing/about-plans.md) (Ověřeno k 7. listopadu 2026).
* Konfigurace zpoždění odpovědi mock serveru přes hlavičky: [Postman Learning Hub - Mock with API (x-mock-response-delay)](https://learning.postman.com/docs/design-apis/mock-apis/tutorials/mock-with-api).
* Jak server Postman mock odpovídá požadavkům na uložené příklady: [Postman Learning Hub - Matching Algorithm](https://learning.postman.com/docs/design-apis/mock-apis/mock-servers/matching-algorithm/).

---
## Jak spustit testy

1. Stáhněte si JSON soubor s kompletní konfigurací z repozitáře: [postman/Payment_Service_Mock.postman_collection.json](../postman/Payment_Service_Mock.postman_collection.json).
2. Otevřete aplikaci Postman a klikněte na tlačítko **Import** v levém horním rohu.
3. Nahrajte stažený `.json` soubor. Kolekce se automaticky vytvoří včetně všech skriptů, proměnných a testovacích příkladů.
4. Otevřete záložku **Variables** u kolekce a do sloupce **Initial Value** u proměnné `mock_url` vložte vygenerovanou adresu vašeho mock serveru (např. `a036a918-45b7-4b26-b1ba-4315c6261b8d.mock.pstmn.io` - bez protokolu `https://`).
5. Požadavky spouštějte v záložce kolekce.
