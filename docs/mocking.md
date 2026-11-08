# Integrační testování: Návrh odpovědí mocku platební služby

Tento dokument obsahuje revidovaný návrh chování mock serveru pro fiktivní platební službu (endpoint `POST /payments`) a definici očekávaného chování objednávkového systému. Dokument slouží jako podklad pro diskuzi s analytikem a obsahuje technický návod k implementaci v nástroji Postman.

## Souhrnná tabulka testovacích scénářů (Návrh pro analytika)

*Poznámka autora: Všechna očekávání od objednávkového systému jsou v této fázi považována za kvalifikované předpoklady a náměty k diskuzi. Ve fiktivní specifikaci se nenacházejí. Objednávkový systém v tomto projektu neexistuje, proto je sloupec „Skutečný výsledek“ prázdný.*

| Odpověď mocku | Co se očekává od objednávky (Návrh do diskuze) | Zdroj / Typ informace | Skutečný výsledek v logu / screenshot |
| :--- | :--- | :--- | :--- |
| **200 OK** + `{"status":"PAID"}` | Systém by měl objednávku přepnout do stavu „Zaplaceno“ a spustit proces expedice. | **Specifikace** (pro HTTP/JSON) / **Předpoklad autora** (pro workflow) | *neprovedeno* |
| **402 Payment Required** + `{"status":"DECLINED"}` | Systém by měl objednávku ponechat v rozpracovaném stavu, uživateli zobrazit chybovou hlášku a nabídnout změnu karty. **[OTÁZKA NA ANALYTIKA: Chceme objednávku po X neúspěšných pokusech stornovat automaticky?]** | **Specifikace** (pro HTTP/JSON) / **Otázka na analytika** (pro workflow a textaci) | *neprovedeno* |
| **500 Internal Server Error** | Systém by měl chybu zalogovat do monitoringu, uživateli zobrazit obecné varování a zachovat stav objednávky. **[OTÁZKA NA ANALYTIKA: Budeme implementovat automatický retry mechanismus na pozadí?]** | **Předpoklad** (simulace chybového stavu) / **Otázka na analytika** | *neprovedeno* |
| **Pomalá odpověď** (mock odpoví `200` po 10 s) | Chování závisí na časovém limitu, který má objednávkový systém při volání brány. **[OTÁZKA NA ANALYTIKA: Jaký je časový limit volání platební brány a co se stane po jeho překročení? Existuje GET endpoint na ověření stavu visící platby?]** Návrh do diskuze: objednávku nestornovat, označit ji jako „Ověřování“ a spustit asynchronní kontrolu. | **Předpoklad** (simulace sítě) / **Otázka na analytika** | *neprovedeno* |
| **200 OK** + prázdné tělo | Systém musí bezpečně ošetřit selhání parsování (nesmí spadnout), transakci neuznat a zalogovat kritickou chybu. **[OTÁZKA NA ANALYTIKA: Jak komunikovat nevalidní data brány koncovému klientovi?]** | **Předpoklad** (detekce nekonzistence) / **Otázka na analytika** | *neprovedeno* |

*Poznámka k pomalé odpovědi: skutečný timeout (žádná odpověď) nastane jen tehdy, když má volající nastavený limit kratší než 10 s. Tento scénář zatím nesimulujeme, mock pouze zpožďuje odpověď. [OVĚŘIT: nastavení časového limitu požadavku v Postmanu]*

---

## Technická implementace v Postmanu

Celá konfigurace mocku je navržena tak, aby byla přenositelná v rámci jednoho JSON souboru kolekce. Veškerá stavová logika je uložena v proměnných kolekce (**Collection Variables**).

### Architektura kolekce
Kolekce obsahuje pouze jeden požadavek. Původně zamýšlený náhodný režim byl odstraněn, protože nepředvídatelný běh generoval při každém spuštění jiné pokrytí scénářů, což je pro regresní testování nevhodné.

Definice dat mocku i samotný volající jsou sloučeny do jednoho prvku:
* **`Zpracovat platbu`** – testovací požadavek se sekvenční rotací scénářů. Přímo pod ním je uloženo 5 příkladů (Examples) s unikátními názvy: `Scenario_PAID`, `Scenario_DECLINED`, `Scenario_500`, `Scenario_Empty` a `Scenario_Timeout`.

### Správa proměnných (Důležité pro import)
Aby byla kolekce funkční ihned po importu, hodnoty musí být zapsány v polích **Initial Value**. První export kolekce měl proměnné prázdné, protože byly vyplněny jen v *Current Value*.

Při prázdné proměnné `scenarios` pravděpodobně selže Pre-request skript v Runneru chybou skriptu (*Errors*), nikoli chybou testu (*Failed*), protože `JSON.parse()` neumí zpracovat prázdný řetězec. **[OVĚŘIT: toto je zatím předpoklad, hlášku jsem nepozoroval.]**

V tabulce proměnných kolekce jsou nastaveny:
* `scenarios` (Initial Value): `["Scenario_PAID", "Scenario_DECLINED", "Scenario_500", "Scenario_Empty", "Scenario_Timeout"]`
* `sequential_index` (Initial Value): `0`
* `mock_url` (Initial Value): prázdná. Adresa se získá po vytvoření vlastního Mock Serveru nad naimportovanou kolekcí (viz návod níže).

### Adresa mock serveru
Adresa mock serveru není součástí repozitáře. Veřejný mock server může volat kdokoli, kdo adresu zná, a při vytvoření patří k účtu autora. Čtenář si proto po importu vytvoří vlastní mock server.

---

## Skripty a simulace negativních stavů /AI

### Pre-request Script pro `Zpracovat platbu`
**[OVĚŘIT: Reset indexu na začátku (blok „KONTROLA PRO RUNNER“) podle mého pozorování nefunguje. V Runneru s `sequential_index` = 3 začala první iterace scénářem `Scenario_Empty`, ne `PAID`. Do opravy kolekce a nového exportu zkopírovat skript z exportu.]**

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

---

## Ověření a doložení chybového stavu (Smoke test mocku)

Následující kód je v záložce **Tests** požadavku `Zpracovat platbu`. Slouží výhradně jako **smoke test funkčnosti samotného mocku** (ověřuje, že Postman vybral správný příklad). Nedokáže ověřit chování objednávkového systému.

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

// --- KONTROLA DOBY ODEZVY (SABOTÁŽ PRO SCENARIO_TIMEOUT) ---
if (activeScenario === "Scenario_Timeout") {
    // !!! SABOTÁŽ TESTU !!! Nastaveno na 100ms, aby test při 10s delayi garantovaně selhal.
    let maxAllowedResponseTime = 100; 
    
    pm.test(`[${activeScenario}] - Kontrola timeoutu (Odezva do ${maxAllowedResponseTime}ms)`, function () {
        pm.expect(pm.response.responseTime).to.be.below(maxAllowedResponseTime);
    });
}

// --- TEST 2: Kontrola obsahu a struktury těla (Body) ---
if (activeScenario === "Scenario_Empty") {
    
    pm.test(`[${activeScenario}] - Tělo odpovědi je zcela prázdné`, function () {
        // Ověříme, že délka textu odpovědi je 0
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
        
        // Ověříme strukturu (klíč "status")
        pm.expect(jsonData).to.have.property("status");
        
        // Ověříme konkrétní hodnotu (PAID nebo DECLINED)
        let expectedValue = activeScenario.replace("Scenario_", ""); // Odřízne "Scenario_" a nechá jen PAID/DECLINED
        pm.expect(jsonData.status).to.equal(expectedValue);
    });
}
```

**Známé omezení:** test u scénáře `Scenario_Timeout` kontroluje jen status `200`. Nekontroluje, že odpověď skutečně přišla se zpožděním. Pokud by hlavička zpoždění přestala fungovat, test zůstane zelený. **[OVĚŘIT: doplnit kontrolu doby odezvy a znovu ověřit sabotáží.]**

---

### Ověření hromadného běhu (Collection Runner)
Požadavek byl spuštěn v nástroji **Collection Runner** s počtem **5 iterací**. Před spuštěním byl `sequential_index` nastaven na `3`. První iterace proto začala scénářem `Scenario_Empty`, následovaly `Scenario_Timeout`, `Scenario_PAID`, `Scenario_DECLINED` a pátá `Scenario_500`. Všech 5 průchodů proběhlo úspěšně a aserce ověřily očekávané HTTP kódy i struktury odpovědí. Výsledek je doložen na [screenshotu z výsledků Runneru](../screenshots/Payment_service_Mock_Run_Results.png), [screenshotu z Postman Console](../screenshots/Payment_service_Mock_Run_Console.png).

Pozorování: reset indexu v kódu se v tomto běhu neuplatnil (první iterace nezačala na `PAID`). **[OVĚŘIT po opravě: zopakovat běh a zapsat, jak se reset chová.]**

---

### Doložení sabotáže (Ověření, že test umí selhat)
Aby bylo prokazatelné, že testy pouze pasivně neprocházejí, byl proveden test sabotáže:
1. U uloženého příkladu `Scenario_DECLINED` byl záměrně změněn návratový status kód z `402 Payment Required` na `200 OK`.
2. Při ručním spuštění požadavku s indexem `1` testovací aserce selhala a vygenerovala červenou chybovou hlášku:
   `AssertionError: expected response to have status code 402 but got 200`

Tím bylo ověřeno, že aserce umí zachytit změnu chování mocku. Vizuální doložení je na [screenshotu sabotáže](../screenshots/Payment_service_Scenario_DECLINED_Sabotage.png). Po sabotáži byl příklad vrácen na `402`.

---

## Bezpečnost a metadata při exportu
Při exportu kolekce vygeneruje Postman v JSON struktuře pole `_exporter_id`. Je to číselný identifikátor účtu v Postmanu. Bylo vědomě rozhodnuto ponechat jej v souboru, protože neobsahuje hesla ani klíče. Adresa mock serveru není v souboru ani ve screenshotech.

---

## Odkazy a zdroje
* Pravidla pro neomezené využití mocků: [Postman Docs - About plans](https://learning.postman.com/latest-v-12/docs/billing/about-plans.md) (ověřeno k 7. listopadu 2026).
* Konfigurace zpoždění odpovědi mock serveru přes hlavičky: [Postman Learning Hub - Mock with API (x-mock-response-delay)](https://learning.postman.com/docs/design-apis/mock-apis/tutorials/mock-with-api).
* Jak server Postman mock odpovídá požadavkům na uložené příklady: [Postman Learning Hub - Matching Algorithm](https://learning.postman.com/docs/design-apis/mock-apis/mock-servers/matching-algorithm/).

---

## Jak spustit testy

1. Stáhněte si JSON soubor kolekce z repozitáře: [postman/Payment_Service_Mock.postman_collection.json](../postman/Payment_Service_Mock.postman_collection.json).
2. Otevřete aplikaci Postman a klikněte na tlačítko **Import** v levém horním rohu.
3. Vytvořte nad naimportovanou kolekcí vlastní Mock Server: klikněte na tři tečky `...` u názvu kolekce, zvolte **Mock collection**, zadejte libovolný název a klikněte na **Create Mock Server**. Zkopírujte vygenerovanou adresu.
4. Otevřete záložku **Variables** u kolekce a do sloupce **Initial Value** u proměnné `mock_url` vložte svou adresu mock serveru jako čistou doménu bez `https://` na začátku (tvar `<vase-id>.mock.pstmn.io`).
5. Před spuštěním v Runneru nastavte `sequential_index` na `0`, aby běh začal scénářem `Scenario_PAID`.
6. Požadavek spouštějte v Collection Runneru (5 iterací) nebo ručně tlačítkem Send.

---

## Stav

Poslední ověřený zelený běh: **[DOPLNIT po novém běhu s novým mock serverem]**. Rozsah ověření: smoke test mocku, požadavek `Zpracovat platbu`, 5 iterací v Runneru.
