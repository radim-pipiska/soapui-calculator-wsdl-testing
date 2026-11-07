# Integrační testování: Návrh odpovědí mocku platební služby

Tento dokument obsahuje revidovaný návrh chování mock serveru pro fiktivní platební službu (endpoint `POST /payments`) a definici očekávaného chování objednávkového systému. Dokument slouží jako podklad pro diskuzi s analytikem a obsahuje technický návod k implementaci v nástroji Postman.

## Souhrnná tabulka testovacích scénářů (Návrh pro analytika)

*Poznámka autora: Všechna očekávání od objednávkového systému jsou v této fázi považována za kvalifikované předpoklady a náměty k diskuzi. Ve fiktivní specifikaci se nenacházejí.*

| Odpověď mocku | Co se očekává od objednávky (Návrh do diskuze) | Zdroj / Typ informace |
| :--- | :--- | :--- |
| **200 OK** + `{"status":"PAID"}` | Systém by měl objednávku přepnout do stavu „Zaplaceno“ a spustit proces expedice. | **Specifikace** (pro HTTP/JSON) / **Předpoklad autora** (pro workflow) |
| **402 Payment Required** + `{"status":"DECLINED"}` | Systém by měl objednávku ponechat v rozpracovaném stavu, uživateli zobrazit chybovou hlášku a nabídnout změnu karty. **[OTÁZKA NA ANALYTIKA: Chceme objednávku po X neúspěšných pokusech stornovat automaticky?]** | **Specifikace** (pro HTTP/JSON) / **Otázka na analytika** (pro workflow a textaci) |
| **500 Internal Server Error** | Systém by měl chybu zalogovat do monitoringu, uživateli zobrazit obecné varování a zachovat stav objednávky. **[OTÁZKA NA ANALYTIKA: Budeme implementovat automatický retry mechanismus na pozadí?]** | **Předpoklad** (simulace chybového stavu) / **Otázka na analytika** |
| **Pomalá odpověď brány** (Zpoždění 10 s) | Pokud má objednávkový systém nastaven klientský timeout pod 10 s, spojení selže na straně sítě (žádná odpověď). Systém nesmí objednávku stornovat, ale měl by ji interně označit jako „Ověřování“ a spustit asynchronní reconciliation proces. **[OTÁZKA NA ANALYTIKA: Jaký je limit pro timeout na straně našeho klienta?]** | **Předpoklad** (simulace sítě) / **Otázka na analytika** |
| **200 OK** + prázdné tělo | Systém musí bezpečně ošetří selhání parsování (nesmí spadnout), transakci neuznat a zalogovat kritickou chybu. **[OTÁZKA NA ANALYTIKA: Jak komunikovat nevalidní data brány koncovému klientovi?]** | **Předpoklad** (detekce nekonzistence) / **Otázka na analytika** |

---

## Důležitá poznámka k infrastruktuře (Limity Postman Mock Serveru)

* **Ověřeno dne:** 7. listopadu 2026
* **Zdroj informací:** Oficiální dokumentace Postman ([Postman Docs - About plans](https://postman.com))

Podle oficiálních podkladů k platformě Postman (od změn zavedených v březnu 2026) **již není využití mock serverů účtováno podle spotřeby a je zcela neomezené na všech plánech**, tedy včetně bezplatného (Free) plánu.

> *"Mock Servers and Custom Domains will no longer be charged based on consumption. Mock server usage is now unlimited on all plans."*

### Upozornění na neaktuální zdroje
Některé starší nebo sekundární zdroje třetích stran stále uvádějí historický limit 1 000 volání měsíčně pro Free plán. Tyto údaje jsou neaktuální. Při konfiguraci testovacího prostředí má oficiální produktová dokumentace Postmanu jednoznačnou přednost. Vzhledem k tomu, že se licenční podmínky a ceny poskytovatelů mění, je platnost tohoto pravidla fixována k výše uvedenému datu ověření.

---

## Technická implementace v Postmanu

Celá konfigurace mocku je navržena tak, aby byla plně přenositelná v rámci jednoho JSON souboru kolekce. Veškerá stavová logika je uložena v proměnných kolekce (**Collection Variables**).

### Architektura kolekce
Kolekce obsahuje přesně dva požadavky. Aby se zamezilo nechtěnému chování a duplicitám při párování, je pět unikátních příkladů (Examples: `Scenario_PAID`, `Scenario_DECLINED`, `Scenario_500`, `Scenario_Empty` a `Scenario_Timeout`) uloženo výhradně pod prvním požadavkem. Mock server Postmanu prohledává celou kolekci, takže tyto příklady jsou plně dostupné pro oba režimy volání:

1. **`Zpracovat platbu (Sequential)`** – Testovací požadavek pro deterministické testování. Postupně střídá stavy od indexu 0 do 4. Obsahuje v sobě uložené šablony odpovědí (Examples).
2. **`Zpracovat platbu (Randomized)`** – Testovací požadavek pro průzkumné testování robustnosti. *Upozornění: Tento režim je nevhodný pro regresní testování, protože odlišný a nepředvídatelný běh generuje při každém spuštění jiné pokrytí kódu.*

### Správa proměnných (Důležité pro import)
Aby byla kolekce funkční ihned po importu, výchozí hodnoty jsou zapsány v polích **Initial Value** (v rozhraní Postmanu jako *Shared Value*). Pokud by byly vyplněny pouze v *Current Value*, exportovaný JSON by proměnné neobsahoval. Pokus o spuštění Pre-request skriptu by v takovém případě selhal v prostředí Postman Runneru s chybou:
`SyntaxError: Unexpected end of JSON input`
K této chybě dochází proto, že metoda `JSON.parse()` nedokáže zpracovat prázdný řetězec, což bylo autorem experimentálně ověřeno.

V tabulce proměnných kolekce jsou nastaveny tyto výchozí hodnoty:
* `scenarios` (Initial Value): `["Scenario_PAID", "Scenario_DECLINED", "Scenario_500", "Scenario_Empty", "Scenario_Timeout"]`
* `sequential_index` (Initial Value): `0`
* `mock_url` (Initial Value): `a036a918-45b7-4b26-b1ba-4315c6261b8d.mock.pstmn.io` (Adresa cvičného mock serveru. Je ponechána záměrně veřejná, protože neobsahuje žádné tajné klíče ani citlivá produkční data a slouží pouze pro akademické účely).

---

## Zdrojové skripty z exekuce (Zdroj pravdy z exportu JSON)

### 1. Požadavek: `Zpracovat platbu (Sequential)`

**Pre-request Script (Before request):**
```javascript
// 1. Načteme pole scénářů z proměnných kolekce
let scenarios = JSON.parse(pm.collectionVariables.get("scenarios"));

// === KONTROLA PRO RUNNER ===
// Reset indexu na 0 provedeme POUZE v případě, že se jedná o první iteraci v automatizovaném Runneru.
// Při běžném ručním klikání přes tlačítko Send se podmínka přeskočí, což umožňuje rotaci stavů.
if (pm.info.eventName === "runner" && pm.info.iteration === 0) {
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

**Test Script:**
```javascript
// 1. Zjistíme aktivní scénář z proměnné kolekce
let activeScenario = pm.collectionVariables.get("next_scenario");

// 2. Definujeme očekávané HTTP status kódy
let expectedStatuses = {
    "Scenario_PAID": 200,
    "Scenario_DECLINED": 402,
    "Scenario_500": 500,
    "Scenario_Empty": 200,
    "Scenario_Timeout": 200
};
let expectedStatusCode = expectedStatuses[activeScenario];

// --- TEST 1: Kontrola HTTP Status kódu (Smoke test funkčnosti mocku) ---
pm.test(`[${activeScenario}] - Status kód je ${expectedStatusCode}`, function () {
    pm.response.to.have.status(expectedStatusCode);
});

// --- TEST 2: Kontrola obsahu a struktury těla (Body) ---
if (activeScenario === "Scenario_Empty") {
    
    pm.test(`[${activeScenario}] - Tělo odpovědi je zcela prázdné`, function () {
        pm.expect(pm.response.text().length).to.equal(0);
    });

} else if (activeScenario === "Scenario_500") {

    pm.test(`[${activeScenario}] - Obsahuje chybovou zprávu serveru`, function () {
        let jsonData = pm.response.json();
        pm.expect(jsonData).to.have.property("error");
        pm.expect(jsonData.error).to.equal("Internal Server Error");
    });

} else if (activeScenario === "Scenario_PAID" || activeScenario === "Scenario_DECLINED") {

    pm.test(`[${activeScenario}] - Obsahuje validní JSON status`, function () {
        let jsonData = pm.response.json();
        pm.expect(jsonData).to.have.property("status");
        
        let expectedValue = activeScenario.replace("Scenario_", ""); 
        pm.expect(jsonData.status).to.equal(expectedValue);
    });
}
```

### 2. Požadavek: `Zpracovat platbu (Randomized)`

**Pre-request Script (Before request):**
```javascript
// 1. Načteme pole scénářů z proměnných kolekce
let scenarios = JSON.parse(pm.collectionVariables.get("scenarios"));

// 2. Vygenerujeme náhodný index (0 až 4)
let randomIndex = Math.floor(Math.random() * scenarios.length);

// 3. Vybereme náhodný scénář
let currentScenario = scenarios[randomIndex];

// 4. Uložíme ho do proměnné pro hlavičku x-mock-response-name a Test skript
pm.collectionVariables.set("next_scenario", currentScenario);

// Zajištění podpory zpoždění i pro náhodný režim
if (currentScenario === "Scenario_Timeout") {
    pm.request.headers.add({ key: "x-mock-response-delay", value: "10000" });
    console.log("-> [RANDOMIZED] Aktivována simulace zpoždění odpovědi (10s)");
} else {
    pm.request.headers.add({ key: "x-mock-response-delay", value: "0" });
}

console.log("-> [RANDOMIZED] Mock přepnut na náhodný scénář: " + currentScenario);
```

