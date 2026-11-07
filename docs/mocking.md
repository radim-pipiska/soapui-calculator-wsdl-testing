# Integrační testování: Návrh odpovědí mocku platební služby

Tento dokument obsahuje revidovaný návrh chování mock serveru pro fiktivní platební službu (endpoint `POST /payments`) a definici očekávaného chování objednávkového systému. Dokument slouží jako podklad pro diskuzi s analytikem a obsahuje technický návod k implementaci v nástroji Postman.

## Souhrnná tabulka testovacích scénářů (Návrh pro analytika)

*Poznámka autora: Všechna očekávání od objednávkového systému jsou v této fázi považována za kvalifikované předpoklady a náměty k diskuzi. Ve fiktivní specifikaci se nenacházejí.*

| Odpověď mocku | Co se očekává od objednávky (Návrh do diskuze) | Zdroj / Typ informace | Skutečný výsledek v logu / screenshot |
| :--- | :--- | :--- | :--- |
| **200 OK** + `{"status":"PAID"}` | Systém by měl objednávku přepnout do stavu „Zaplaceno“ a spustit proces expedice. | **Specifikace** (pro HTTP/JSON) / **Předpoklad autora** (pro workflow) | *neprovedeno* |
| **402 Payment Required** + `{"status":"DECLINED"}` | Systém by měl objednávku ponechat v rozpracovaném stavu, uživateli zobrazit chybovou hlášku a nabídnout změnu karty. **[OTÁZKA NA ANALYTIKA: Chceme objednávku po X neúspěšných pokusech stornovat automaticky?]** | **Specifikace** (pro HTTP/JSON) / **Otázka na analytika** (pro workflow a textaci) | *neprovedeno* |
| **500 Internal Server Error** | Systém by měl chybu zalogovat do monitoringu, uživateli zobrazit obecné varování a zachovat stav objednávky. **[OTÁZKA NA ANALYTIKA: Budeme implementovat automatický retry mechanismus na pozadí?]** | **Předpoklad** (simulace chybového stavu) / **Otázka na analytika** | *neprovedeno* |
| **Pomalá odpověď brány** (Zpoždění 10 s) | Pokud má objednávkový systém nastaven klientský timeout pod 10 s, spojení selže na straně sítě (žádná odpověď). Systém nesmí objednávku stornovat, ale měl by ji interně označit jako „Ověřování“ and spustit asynchronní reconciliation proces. **[OTÁZKA NA ANALYTIKA: Jaký je limit pro timeout na straně našeho klienta?]** | **Předpoklad** (simulace sítě) / **Otázka na analytika** | *neprovedeno* |
| **200 OK** + prázdné tělo | Systém musí bezpečně ošetřit selhání parsování (nesmí spadnout), transakci neuznat a zalogovat kritickou chybu. **[OTÁZKA NA ANALYTIKA: Jak komunikovat nevalidní data brány koncovému klientovi?]** | **Předpoklad** (detekce nekonzistence) / **Otázka na analytika** | *neprovedeno* |

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
Kolekce byla maximálně zjednodušena a obsahuje pouze jeden jediný požadavek. Původně zamýšlený náhodný režim (`Randomized`) byl z architektury zcela odstraněn, protože nepředvídatelný běh generoval při každém spuštění jiné pokrytí kódu, což je pro regresní testování nevhodné.

Definice dat mocku i samotný volající exekutor jsou sloučeny do jednoho prvku:
1. **`Zpracovat platbu`** – Testovací požadavek s integrovanou sekvenční rotací indexů. Přímo pod ním je uloženo 5 unikátních příkladů (Examples): `Scenario_PAID`, `Scenario_DECLINED`, `Scenario_500`, `Scenario_Empty` a `Scenario_Timeout`.

### Správa proměnných (Důležité pro import)
Aby byla kolekce funkční ihned po importu, hodnoty musí být striktně zapsány v polích **Initial Value**. Pokud by byly vyplněny pouze v *Current Value*, exportovaný JSON bude prázdný a Pre-request skript selže v Runneru s chybou `SyntaxError`, protože metoda `JSON.parse()` nedokáže zpracovat prázdný řetězec, což bylo autorem experimentálně ověřeno.

In table of collection variables set:
* `scenarios` (Initial Value): `["Scenario_PAID", "Scenario_DECLINED", "Scenario_500", "Scenario_Empty", "Scenario_Timeout"]`
* `sequential_index` (Initial Value): `0`
* `mock_url` (Initial Value): *Zde hodnotitel ponechá pole prázdné. Adresa se vygeneruje automaticky po vytvoření vlastního Mock Serveru nad naimportovanou kolekcí.*

### Bezpečnost a ochrana firemního účtu
V kolekci ani v dokumentaci záměrně není poskytnuta konkrétní živá URL adresa mock serveru. Vzhledem k tomu, že testování probíhá pod firemním účtem, sdílení aktivního koncového bodu by porušovalo bezpečnostní politiku. Projekt je navržen jako plně přenositelná (Portable) sada – hodnotitel si po importu vygeneruje vlastní mock endpoint, čímž je zaručena stoprocentní izolace a bezpečnost.

---

## Skripty a simulace negativních stavů /AI

### Pre-request Script pro `Zpracovat platbu`
```javascript
// 1. Načteme pole scénářů z proměnných kolekce
let scenarios = JSON.parse(pm.collectionVariables.get("scenarios"));

// === OPRAVENÁ KONTROLA PRO RUNNER ===
// Index zresetujeme na 0 pouze tehdy, pokud test běží uvnitř automatizovaného Runneru 
// A ZÁROVEŇ jsme v úplně první iteraci. Při ručním klikání (Send) se tato podmínka ignoruje.
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
    console.log("-> [MOCK] Aktivována simulace pomalé odpovědi (delay 10s)");
} else {
    // Pro ostatní scénáře vynutíme okamžitou odpověď (0ms)
    pm.request.headers.add({ key: "x-mock-response-delay", value: "0" });
}

console.log("-> [MOCK] Vybrána odpověď: " + currentScenario);

// 5. Vypočítáme další index v pořadí a uložíme ho zpět do sequential_index
let nextIndex = (currentIndex + 1) % scenarios.length;
pm.collectionVariables.set("sequential_index", nextIndex);
```

---

## Ověření a doložení chybového stavu (Smoke test mocku)

Následující kód se vkládá do záložky **Tests** požadavku. Slouží výhradně jako **smoke test funkčnosti samotného mocku** (ověřuje, že Postman vybral správný příklad). Nedokáže ověřit chování externího objednávkového systému.

**Smoke test skript/AI:**
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

// --- TEST 1: Kontrola HTTP Status kódu ---
pm.test(`[${activeScenario}] - Status kód je ${expectedStatusCode}`, function () {
    pm.response.to.have.status(expectedStatusCode);
});

// --- TEST 2: Kontrola obsahu a struktury těla (Body) ---
if (activeScenario === "Scenario_Empty") {
    
    pm.test(`[${activeScenario}] - Tělo odpovědi je zcela prázdné`, function () {
        // Ověříme, že délka textu odpovědi je 0
        pm.expect(pm.response.text().length).to.equal(0);
    });

} else if (activeScenario === "Scenario_500") {

    pm.test(`[${activeScenario}] - Obsahuje chybovou zprávu serveru`, function () {
        let jsonData = pm.response.json();
        jsonData.expect(jsonData).to.have.property("error");
        pm.expect(jsonData.error).to.equal("Internal Server Error");
    });

} else if (activeScenario === "Scenario_PAID" || activeScenario === "Scenario_DECLINED") {

    pm.test(`[${activeScenario}] - Obsahuje validní JSON status`, function () {
        let jsonData = pm.response.json();
        
        // Ověříme strukturu (klíč "status")
        pm.expect(jsonData).to.have.property("status");
        
        // Ověříme konkrétní hodnotu (PAID nebo DECLINED)
        let expectedValue = activeScenario.replace("Scenario_", ""); // Odřízne "Scenario_" a nechá jen PAID/DECLINED
        pm.expect(jsonData.status).to.equal(expectedValue);
    });
}
```

---

### Ověření úspěšného hromadného běhu (Collection Runner)
Pro validaci kompletní série integračních scénářů byl požadavek spuštěn v nástroji **Collection Runner** s nastaveným počtem **5 iterací**. Při spuštění byl v proměnných kolekce přednastaven `sequential_index` na hodnotu `3`. První iterace z Runneru proto korektně odstartovala scénářem `Scenario_Empty` a celý cyklus postupně otestoval všech 5 definovaných stavů, přičemž pátá iterace byla zakončena scénářem `Scenario_500`.

