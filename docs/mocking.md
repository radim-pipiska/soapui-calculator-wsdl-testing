# Integrační testování: Návrh odpovědí mocku platební služby

Tento dokument obsahuje návrh chování mock serveru pro platební službu (endpoint `POST /payments`) a definici očekávaných reakcí objednávkového systému. Slouží jako podklad pro vývoj, testování a diskuzi s analytikem.

## Souhrnná tabulka testovacích scénářů

| Odpověď mocku | Co očekávám od objednávky | Zdroj |
| :--- | :--- | :--- |
| **200 OK** + `{"status":"PAID"}` | Objednávka přejde do stomu „Zaplaceno“ a spustí se expedice. | **Specifikace** (pro HTTP a JSON) / **Předpoklad** (pro chování objednávky) |
| **402 Payment Required** + `{"status":"DECLINED"}` | Objednávka se nestornuje, uživateli se zobrazí chyba a možnost změnit kartu. | **Specifikace** (pro HTTP a JSON) / **Otázka na analytika** (pro workflow a textaci) |
| **500 Internal Server Error** | Chyba se zaloguje, uživatel vidí obecné varování, stav objednávky se nemění. | **Předpoklad** (simulace mocku) / **Otázka na analytika** (chceme automatický retry?) |
| **Timeout** (žádná odpověď) | Systém neprovádí storno, přepne do stavu „Ověřování“ a naplánuje asynchronní kontrolu. | **Předpoklad** (simulace mocku) / **Otázka na analytika** (jaký je proces ověření visících plateb?) |
| **200 OK** + prázdné tělo | Aplikace bezpečně ošetří selhání parsování, nezmění stav na zaplaceno a zaloguje error. | **Předpoklad** (simulace mocku) / **Otázka na analytika** (jak komunikovat nečekanou chybu klientovi?) |

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

Celá konfigurace mocku je navržena tak, aby byla plně přenositelná a izolovaná. Veškerá logika i stavové proměnné jsou uloženy přímo v **Collection Variables** (proměnných kolekce). Exportovaný JSON soubor kolekce je tak jediným zdrojem pravdy a nevyžaduje import žádného externího Environmentu.

### Inicializované proměnné v kolekci (Collection Variables)
* `scenarios`: `["Scenario_PAID", "Scenario_DECLINED", "Scenario_500", "Scenario_Empty", "Scenario_Timeout"]`
* `sequential_index`: `0`

### 1. Režim: Zpracovat platbu (Sequential)
Tento požadavek slouží k deterministickému testování. Využívá záložku **Pre-request Script** k postupnému procházení polí scénářů stále dokola.

**Pre-request Script:**
```javascript
// 1. Načteme pole scénářů z proměnných kolekce
let scenarios = JSON.parse(pm.collectionVariables.get("scenarios"));

// 2. Načteme izolovaný index pro sekvenční volání
let currentIndex = parseInt(pm.collectionVariables.get("sequential_index"));

if (isNaN(currentIndex)) {
    currentIndex = 0;
}

// 3. Vybereme scénář
let currentScenario = scenarios[currentIndex];

// 4. Uložíme ho do proměnné pro hlavičku x-mock-response-name
pm.collectionVariables.set("next_scenario", currentScenario);
console.log("-> [SEQUENTIAL] Mock přepnut na scénář: " + currentScenario);

// 5. Vypočítáme další index v pořadí a uložíme ho zpět do sequential_index
let nextIndex = (currentIndex + 1) % scenarios.length;
pm.collectionVariables.set("sequential_index", nextIndex);
```

### 2. Režim: Zpracovat platbu (Randomized)
Tento požadavek simuluje nestabilitu reálného prostředí a náhodné výpadky. Neovlivňuje čítač sekvenčního režimu.

**Pre-request Script:**
```javascript
// 1. Načteme pole scénářů z proměnných kolekce
let scenarios = JSON.parse(pm.collectionVariables.get("scenarios"));

// 2. Vygenerujeme náhodný index (0 až 4)
let randomIndex = Math.floor(Math.random() * scenarios.length);

// 3. Vybereme náhodný scénář
let currentScenario = scenarios[randomIndex];

// 4. Uložíme ho do proměnné pro hlavičku x-mock-response-name
pm.collectionVariables.set("next_scenario", currentScenario);
console.log("-> [RANDOMIZED] Mock přepnut na scénář: " + currentScenario);
```

---

## Definice datových struktur mock odpovědí (Examples)

Každému scénáři odpovídá v Postmanu jeden uložený **Example** s unikátním názvem. Vyhledávání je řízeno hlavičkou požadavku `x-mock-response-name: {{next_scenario}}`.

### Scenario_PAID (Status: `200 OK`)
```json
{
    "status": "PAID"
}
```

### Scenario_DECLINED (Status: `402 Payment Required`)
```json
{
    "status": "DECLINED"
}
```

### Scenario_500 (Status: `500 Internal Server Error`)
```json
{
    "error": "Internal Server Error"
}
```

### Scenario_Empty (Status: `200 OK`)
*Tělo odpovědi je prázdné (0 bajtů).*

### Scenario_Timeout (Status: `200 OK`)
*Simulační zpráva. V reálném testování je timeout vyvolán nastavením nízké hodnoty pro timeout na straně volajícího klienta.*
```json
{
    "info": "Tato odpoved simuluje vyprseni casoveho limitu"
}
```

---

## Automatizovaná validace odpovědí (Záložka Tests)

Oba požadavky sdílejí tento identický testovací skript. Ten se dynamicky adaptuje na základě toho, jaký scénář byl v daném kroku zrovna vybrán, a ověří jak HTTP status kód, tak integritu dat v těle odpovědi.

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

// --- TEST 1: Kontrola HTTP Status kódu ---
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

---

## Jak spustit testy

1. Stáhněte si JSON soubor s kompletní konfigurací z repozitáře: [postman/Payment_Service_Mock.postman_collection.json](postman/Payment_Service_Mock.postman_collection.json).
2. Otevřete aplikaci Postman a klikněte na tlačítko **Import** v levém horním rohu.
3. Nahrajte stažený `.json` soubor. Kolekce se automaticky vytvoří včetně všech skriptů, proměnných a testovacích příkladů.
4. Klikněte pravým tlačítkem na importovanou kolekci a vytvořte nad ní **Mock Server** (případně využijte lokální mockovací endpoint).
5. Spusťte požadavky ručně nebo hromadně pomocí nástroje **Collection Runner**. Výsledky asercí se zobrazí v záložce *Test Results*.
