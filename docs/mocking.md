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
Aby byla kolekce funkční ihned po importu, hodnoty musí být zapsány ve sloupci **Initial Value** (v novějších verzích Postmanu označeném *Shared value*). První export kolekce měl proměnné prázdné, protože byly vyplněny jen v *Current Value* (*Local value*).

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
Skript rotuje scénáře podle proměnné `sequential_index`. Při každém odeslání vybere scénář na tomto indexu, nastaví hlavičky a posune index o jedna (po posledním scénáři se vrací na 0). **[OVĚŘIT: před publikací zkopírovat skript z finálního exportu a porovnat.]**

```javascript
// 1. Načteme pole scénářů z proměnných kolekce
let scenarios = JSON.parse(pm.collectionVariables.get("scenarios"));

// 2. Načteme index pro sekvenční volání
let currentIndex = parseInt(pm.collectionVariables.get("sequential_index"));

// Pojistka pro případ prázdné hodnoty
if (isNaN(currentIndex)) {
    currentIndex = 0;
}

// 3. Vybereme scénář
let currentScenario = scenarios[currentIndex];

// 4. Uložíme ho do proměnné pro hlavičku a pro Test skript
pm.collectionVariables.set("next_scenario", currentScenario);

// Simulace pomalé odpovědi (zpoždění na straně mock serveru)
if (currentScenario === "Scenario_Timeout") {
    // Hlavička Postman mocku pro umělé zpoždění odpovědi v ms
    pm.request.headers.add({ key: "x-mock-response-delay", value: "10000" });
    console.log("-> [SEQUENTIAL] Aktivována simulace zpoždění (delay 10s)");
} else {
    // Pro ostatní scénáře vynutíme okamžitou odpověď (0 ms)
    pm.request.headers.add({ key: "x-mock-response-delay", value: "0" });
}

console.log("-> [SEQUENTIAL] Vybrána odpověď: " + currentScenario);

// 5. Vypočítáme další index v pořadí a uložíme ho zpět do sequential_index
let nextIndex = (currentIndex + 1) % scenarios.length;
pm.collectionVariables.set("sequential_index", nextIndex);
```

### Proč skript sám nerozlišuje ruční Send a Runner
Zkoušel jsem do skriptu přidat automatický reset indexu na 0 na začátku Runneru. Nefungoval:
* **Zdokumentováno:** `pm.info.eventName` nabývá u HTTP požadavku jen hodnot `prerequest` a `test` ([Postman Docs – pm.info](https://learning.postman.com/docs/tests-and-scripts/write-scripts/postman-sandbox-reference/pm-info)). Podmínka `eventName === "runner"` proto nemůže nikdy platit.
* **Pozorování autora:** podmínka založená jen na `pm.info.iteration === 0` resetovala index i při každém ručním Send, takže ruční odesílání zůstávalo na prvním scénáři. Dokumentace popisuje `iteration` jako aktuální iteraci běhu kolekce a o ručním Send nic neuvádí, příčinu jsem tedy neověřil.
* **Rozhodnutí:** skript žádný automatický reset neobsahuje. Index se před během v Runneru nastavuje ručně na `0` (viz návod níže). Ruční Send pokračuje v rotaci podle aktuální hodnoty indexu.

---

## Ověření a doložení chybového stavu (Smoke test mocku)

Následující kód je v záložce **Tests** požadavku `Zpracovat platbu`. Slouží výhradně jako **smoke test funkčnosti samotného mocku** (ověřuje, že Postman vybral správný příklad a že zpoždění funguje). Nedokáže ověřit chování objednávkového systému. **[OVĚŘIT: před publikací porovnat s finálním exportem. Verze v dokumentu používá finální podmínku zpoždění, sabotovaná verze (`below 100`) je popsána níže.]**

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

// --- KONTROLA DOBY ODEZVY (jen pro Scenario_Timeout) ---
if (activeScenario === "Scenario_Timeout") {
    // Zpoždění v pre-request skriptu je 10000 ms, dolní hranice má rezervu
    let minExpectedDelay = 9000;

    pm.test(`[${activeScenario}] - Odezva trvala aspoň ${minExpectedDelay} ms`, function () {
        pm.expect(pm.response.responseTime).to.be.above(minExpectedDelay);
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

**Co test ověřuje a co ne:** u `Scenario_Timeout` kontroluje status `200` a že odpověď trvala aspoň 9 s. Neověřuje, jak se zachová objednávkový systém, protože ten v projektu není.

---

### Ověření hromadného běhu (Collection Runner)
Požadavek byl spuštěn v nástroji **Collection Runner** s počtem **5 iterací** a s `sequential_index` nastaveným na `0`. Postman Console zachytila pořadí scénářů: `Scenario_PAID`, `Scenario_DECLINED`, `Scenario_500`, `Scenario_Empty`, `Scenario_Timeout` (screenshot [Console](../screenshots/Payment_service_Mock_Run_Console.png)). Pátý požadavek trval 10 282 ms, což odpovídá nastavenému zpoždění 10 s.

Screenshot [výsledků Runneru](../screenshots/Payment_service_Mock_Run_Results.png) pochází z běhu s **dočasně sabotovanou** kontrolou doby odezvy (viz další sekce). Proto ukazuje 10 testů, z toho 9 úspěšných a 1 očekávaně neúspěšný. Adresa mock serveru byla z tohoto obrázku před uložením ručně odstraněna v grafickém editoru, v Console je skrytá volbou *Hide network*.

---

### Doložení sabotáže (Ověření, že test umí selhat)
Aby bylo prokazatelné, že testy pouze pasivně neprocházejí, byly provedeny dvě sabotáže.

**Sabotáž 1: status kód.**
1. U uloženého příkladu `Scenario_DECLINED` byl záměrně změněn návratový status kód z `402 Payment Required` na `200 OK`.
2. Při ručním spuštění požadavku s indexem `1` testovací aserce selhala:
   `AssertionError: expected response to have status code 402 but got 200`

Vizuální doložení je na [screenshotu sabotáže](../screenshots/Payment_service_Scenario_DECLINED_Sabotage.png). Po sabotáži byl příklad vrácen na `402`.

**Sabotáž 2: doba odezvy.**
1. V Tests byla dočasně nastavena opačná podmínka: odezva `Scenario_Timeout` musí být **pod** 100 ms.
2. V Runneru test selhal: `AssertionError: expected 10282 to be below 100`. To ukazuje, že aserce se vykoná a čte skutečnou dobu odezvy (zpoždění 10 s funguje).
3. Podmínka byla následně nahrazena finální verzí (`above 9000`) zobrazenou výše.

**[OVĚŘIT: finální podmínka `above 9000` zatím sabotáží ověřena nebyla. Test: dočasně nastavit hlavičku `x-mock-response-delay` pro `Scenario_Timeout` na `0`, očekávat červený test, pak vrátit `10000` a zapsat výsledek.]**

---

## Bezpečnost a metadata při exportu
Při exportu kolekce vygeneruje Postman v JSON struktuře pole `_exporter_id`. Je to číselný identifikátor účtu v Postmanu. Bylo vědomě rozhodnuto ponechat jej v souboru, protože neobsahuje hesla ani klíče. Před uložením do repozitáře je potřeba zkontrolovat, že `mock_url` je v exportu prázdná.

---

## Odkazy a zdroje
* Pravidla pro neomezené využití mocků: [Postman Docs - About plans](https://learning.postman.com/latest-v-12/docs/billing/about-plans.md) (ověřeno k 7. listopadu 2026).
* Konfigurace zpoždění odpovědi mock serveru přes hlavičky: [Postman Learning Hub - Mock with API (x-mock-response-delay)](https://learning.postman.com/docs/design-apis/mock-apis/tutorials/mock-with-api).
* Jak server Postman mock odpovídá požadavkům na uložené příklady: [Postman Learning Hub - Matching Algorithm](https://learning.postman.com/docs/design-apis/mock-apis/mock-servers/matching-algorithm/).
* Hodnoty `pm.info.eventName` a `pm.info.iteration`: [Postman Docs - pm.info](https://learning.postman.com/docs/tests-and-scripts/write-scripts/postman-sandbox-reference/pm-info) (ověřeno 8. listopadu 2026).

---

## Jak spustit testy

1. Stáhněte si JSON soubor kolekce z repozitáře: [postman/Payment_Service_Mock.postman_collection.json](../postman/Payment_Service_Mock.postman_collection.json).
2. Otevřete aplikaci Postman a klikněte na tlačítko **Import** v levém horním rohu.
3. Vytvořte nad naimportovanou kolekcí vlastní Mock Server: klikněte na tři tečky `...` u názvu kolekce, zvolte **Mock collection**, zadejte libovolný název a klikněte na **Create Mock Server**. Zkopírujte vygenerovanou adresu.
4. Otevřete záložku **Variables** u kolekce a do sloupce **Initial Value** u proměnné `mock_url` vložte svou adresu mock serveru jako čistou doménu bez `https://` na začátku (tvar `<vase-id>.mock.pstmn.io`).
5. **Před spuštěním v Collection Runneru nastavte `sequential_index` na `0`**, aby běh začal scénářem `Scenario_PAID`. Počet iterací nastavte na 5. Po pěti iteracích se index vrátí na 0.
6. Při ručním odesílání tlačítkem Send se scénáře střídají podle aktuální hodnoty `sequential_index`.

---

## Stav

Poslední ověřený zelený běh: **[DOPLNIT po běhu finální verze kolekce]**. Rozsah ověření: smoke test mocku, požadavek `Zpracovat platbu`, 5 iterací v Runneru.
