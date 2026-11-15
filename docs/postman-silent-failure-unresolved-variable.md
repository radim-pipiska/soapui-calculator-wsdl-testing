# Případová studie: Skrytá past v podobě case-sensitivity proměnných a stavovosti dat v Postmanovi

## 1. Kontext a cíl testu
Při datově řízeném testování (DDT – Data-Driven Testing) REST API pro rezervaci dovolených bylo cílem ověřit byznys pravidlo pro filtrování dnů:
* **Byznys pravidlo:** Státní svátky a víkendy (sobota, neděle) se nesmí zapsat do rezervace.
* **Testovací sada:** Celkem 40 iterací (39 státních svátků + 1 kontrolní pracovní den, např. 20. 8.), celkem 160 testovacích assercí (4 testy na iteraci).
* **Očekávané chování:** V testovaném API jsou úmyslně integrované chyby v logice svátků. Správně běžící test na čisté testovací osobě má proto odhalit **17 chybně zapsaných svátků** (143 zelených, 17 červených testů).

---

## 2. Co se pokazilo (Průběh incidentu)
Testovací sada prošla zdánlivě bez jediné chyby (160/160 zelených), čímž zamaskovala všech 17 reálných defektů v aplikaci (tzv. *false positive* – falešně pozitivní výsledek).

1. **Překlep v názvu proměnné:** V prostředí (Environment) byla definována proměnná `personId` (camelCase), ale v JSON těle požadavku (Body) bylo použito `{{PersonId}}` (PascalCase).
2. **Chování Postmana:** Názvy proměnných v Postmanovi jsou **case-sensitive** (rozlišují velká a malá písmena). Postman proměnnou `{{PersonId}}` nerozpoznal, nevyhodil chybu a místo ID zaměstnance odeslal doslovný text `"{{PersonId}}"` (ověřeno v Postman Console).
3. **Slabá asserce a falešná zelená:** Test neověřoval, že API svátek aktivně *odmítlo*, ale pouze to, že se v odpovědi nic nezapsalo (`"MarkedDays": []`). Protože API na prázdné pole odpovídá stejně pro svátek i pro už dříve zapsané dny, prošly i dny, které měly odhalit chybu.

---

## 3. Hloubková analýza: Vliv stavu databáze na výsledky
Dalším zkoumáním v Postman Console a opakováním běhů se ukázalo, že samotný překlep je jen polovina problému. **Skutečným zdrojem falešně zelených výsledků je kombinace nevalidovaného vstupu a stavu databáze.**

API si pamatuje již zapsané dny a při opakovaném pokusu o zápis vrací `200 OK`, prázdné pole `MarkedDays: []` a zprávu *„Žádné nové dny dovolené (vše již zapsáno nebo jen víkendy/svátky)“*. Doslovný řetězec `"{{PersonId}}"` API přijalo jako regulérní jméno „pseudo-osoby“ a při úplně prvním běhu (v 12:32) na ni dny zapsalo. Každý další běh se stejným řetězcem pak vracel prázdné pole, protože dny už byly v databázi uloženy.

### Přehled a srovnání testovacích běhů

| Čas | Co Postman poslal | Stav osoby v DB | Výsledek (zelené / červené) | Vysvětlení chování |
| :--- | :--- | :--- | :--- | :--- |
| **12:32** | `{{PersonId}}` *(doloženo Console)* | Již existující *(z dřívějších pokusů)* | **160 / 0** | Dny pro tuto „pseudo-osobu“ už byly zapsané. API vrátilo prázdné `MarkedDays: []` a všech 160 assercí prošlo. |
| **12:56** | `RP260` *(správná proměnná)* | Čistá osoba | **143 / 17** | **Správný výsledek.** Test odhalil všech 17 záměrných vad API (např. svátky `2028-12-25` a `2028-12-26` se chybně zapsaly). |
| **13:10** | `{{PersonId}}` *(opakovaný běh)* | Již existující *(vč. 20. 8.)* | **159 / 1** | Zčervenal pouze kontrolní pracovní den (20. 8.), protože pro jméno `{{PersonId}}` už byl zapsaný z dřívějška. |
| **13:20** | `{{PersonID}}` *(jiný překlep)* | Nová „pseudo-osoba“ | **143 / 17** | Nový neexistující řetězec API založilo jako čistou osobu a chovalo se stejně jako u platného ID. |

> **Důležitý poznatek:** Výsledek testu závisí na stavu databáze – rozbitá proměnná prošla bez chyby (160/0) pouze proto, že pro daný řetězec už byla data v databázi zapsaná. Ani kontrolní řádek s pracovním dnem (20. 8.) není spolehlivou ochranou proti rozbité proměnné, pokud test neběží nad čistými daty.

---

## 4. Řešení: Automatický „hlídač“ nevyhodnocených proměnných
Aby test nespoléhal jen na stav dat a okamžitě odhalil jakoukoliv nevyhodnocenou proměnnou `{{...}}` v těle nebo URL požadavku, doplnil jsem do záložky **Scripts** dvoufázovou kontrolu.

*(Poznámka z vývoje: Samotné volání `pm.variables.replaceIn(...)` v Pre-request skriptu nestačí, protože výsledek jen vrátí, ale nikam neuloží ani neověří. Proto je nutné výsledek uložit do lokální proměnné a vyhodnotit v Post-response testu.)*

### 1. Pre-request Script (Detekce a příprava dat)
Skript před odesláním požadavku zkontroluje, zda v těle nebo v URL nezůstaly znaky `{{`, a výsledek uloží do lokálních proměnných.

```javascript
const rawBody = pm.request.body ? (pm.request.body.raw || "") : "";
const rawUrl = pm.request.url.toString();

const resolvedBody = pm.variables.replaceIn(rawBody);
const resolvedUrl = pm.variables.replaceIn(rawUrl);

const unresolved = [];
if (resolvedBody.includes("{{")) unresolved.push("tělo: " + resolvedBody);
if (resolvedUrl.includes("{{")) unresolved.push("URL: " + resolvedUrl);

pm.variables.set("local_varsCheck", unresolved.length === 0 ? "OK" : "CHYBA");
pm.variables.set("local_varsDetail", unresolved.join(" | "));
console.log("[kontrola proměnných]", pm.variables.get("local_varsCheck"));
```

### 2. Post-response Script (Fail-Safe asserce)
Asserce ověří, že kontrola proběhla a dopadla stavem `"OK"`. Díky tomu hlídač **selhává bezpečně (fail-safe)** – pokud by někdo Pre-request skript omylem smazal, vypnul (`return;`) nebo přejmenoval proměnnou, test neskončí zeleně, ale spadne na chybu `expected undefined to equal 'OK'`.

```javascript
pm.test("Všechny proměnné v těle a URL požadavku jsou nahrazeny", function () {
    pm.expect(
        pm.variables.get("local_varsCheck"),
        pm.variables.get("local_varsDetail")
    ).to.equal("OK");
});
```

---

## 5. Ověření funkčnosti hlídače (Testování sabotáží)
Nasazení hlídače rozšířilo sadu ze 160 na **200 testů** (40 iterací × 5 assercí). Funkčnost jsem ověřil řízenou sabotáží vstupů i samotného skriptu:

| Scénář ověření | Výsledek | Co tento běh dokazuje |
| :--- | :--- | :--- |
| **1. Správná proměnná `{{personId}}` (osoba `RP279`), hlídač zapnutý** | **200 testů, 17 červených** | Hlídač je zelený (`Console: OK`), test spolehlivě zachytil 17 záměrných vad API. |
| **2. Rozbitá proměnná `{{PersonId}}`, hlídač zapnutý** | **200 testů, 41 červených** | Hlídač zčervenal ve všech 40 iteracích a vypsal přesné tělo požadavku. Zbývající 1 chyba je kontrolní den 20. 8. (již zapsaný z dřívějška). |
| **3. Správná proměnná, hlídač vypnutý (`return;`)** | **200 testů, 57 červených** | Hlídač **selhává bezpečně** (40× chyba `expected undefined to equal 'OK'` + 17 vad API). Nelze ho potichu vypnout. |

---

## 6. Otevřená otázka na systémového analytika
Vzhledem k tomu, že při testování nebyla k dispozici kompletní specifikace API, nehlásil jsem chování serveru rovnou jako chybu, ale připravil jsem jej jako konstruktivní dotaz k vyjasnění validace vstupů:

> **Otázka na analytika:** *Má API přijmout jakýkoliv libovolný textový řetězec jako `personId` (např. neexistující ID nebo řetězec `"{{PersonId}}"`), založit ho, odpovědět `200 OK` a zapsat mu dovolenou? Neměla by na vstupu probíhat validace formátu či existence zaměstnance v číselníku, a v případě neplatného vstupu vracet klientskou chybu `4xx` (např. `400 Bad Request` nebo `404 Not Found`)?*

---

## 7. Klíčové poznatky pro praxi
* **Izolace testovacích dat je nutnost:** Stejný vstup dává při opakování jiný výsledek podle stavu databáze. Každý běh DDT sady proto musí používat **novou, čistou testovací osobu** (např. `RP261`, `RP262`, `RP279`), nebo po sobě data uklízet.
* **Zelený test ještě neznamená funkční aplikaci:** Vždy je nutné ověřit, že testy dokážou selhat ve chvíli, kdy selhat mají (kontrola proti známým chybám), a že asserce ověřují správný důvod úspěchu.
* **Fail-safe přístup u pomocných skriptů:** Kontroly v testech musí být navržené tak, aby jejich případné vypnutí nebo rozbití vedlo k červenému výsledku, nikoliv k falešné zelené.
