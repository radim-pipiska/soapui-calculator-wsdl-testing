# Případová studie: Skrytá past v podobě case-sensitivity proměnných a stavovosti dat v Postmanovi

> **Rozsah a původ:** Pokusy proběhly 14. 11. 2026 na cvičné kopii kolekce „Kalendář Dovolených – Data-Driven“, ne na kolekci z repozitáře. Vacation API je tréninkové API, zveřejnění potvrdil zadavatel úkolu. Skripty v sekci 4 jsou označeny `/AI`: vznikly s pomocí AI a byly upraveny po sabotáži. Tvrzení označená `[HYPOTÉZA]` jsou odvozená, přímo neověřená.

## 1. Kontext a cíl testu
Při datově řízeném testování (DDT – Data-Driven Testing) REST API pro rezervaci dovolených bylo cílem ověřit byznys pravidlo pro filtrování dnů:
* **Byznys pravidlo:** Státní svátky a víkendy (sobota, neděle) se nesmí zapsat do rezervace (pravidlo ze zadání úkolu; sada zatím testuje jen svátky, víkendy ne).
* **Testovací sada:** Celkem 40 iterací (39 státních svátků + 1 kontrolní pracovní den, např. 20. 8.), celkem 160 testů (4 testy `pm.test` na iteraci).
* **Očekávané chování:** V testovaném API jsou úmyslně integrované chyby v logice svátků. Správně běžící test na čisté testovací osobě má proto odhalit **17 chybně zapsaných svátků** (143 zelených, 17 červených testů).

---

## 2. Co se pokazilo (Průběh incidentu)
Testovací sada prošla zdánlivě bez jediné chyby (160/160 zelených), čímž zamaskovala všech 17 reálných defektů v aplikaci (tzv. falešně zelený test, angl. *false pass*).

1. **Překlep v názvu proměnné:** Mezi proměnnými kolekce (*Collection variables*, běh měl `Environment: none`) byla definována proměnná `personId` (camelCase), ale v JSON těle požadavku (Body) bylo použito `{{PersonId}}` (PascalCase).
2. **Chování Postmana:** Názvy proměnných v Postmanovi jsou **case-sensitive** (rozlišují velká a malá písmena). Postman proměnnou `{{PersonId}}` nerozpoznal, nevyhodil chybu a místo ID zaměstnance odeslal doslovný text `"{{PersonId}}"` (ověřeno v Postman Console).
3. **Slabá asserce a falešná zelená:** Test neověřoval, že API svátek aktivně *odmítlo*, ale pouze to, že se v odpovědi nic nezapsalo (`"MarkedDays": []`). Protože API vrací prázdné `MarkedDays` stejně pro svátek i pro dny, které už jsou zapsané, prošly i dny, které měly odhalit chybu.

---

## 3. Další poznatky: Vliv stavu databáze na výsledky
Dalším zkoumáním v Postman Console a opakováním běhů se ukázalo, že samotný překlep je jen polovina problému. **Pravděpodobným zdrojem falešně zelených výsledků je kombinace nevalidovaného vstupu a stavu databáze** (viz „doloženo“ a „odvozeno“ níže).

API si pamatuje již zapsané dny a při opakovaném pokusu o zápis vrací `200 OK`, prázdné pole `MarkedDays: []` a zprávu *„Žádné nové dny dovolené (vše již zapsáno nebo jen víkendy/svátky)“*. 
**Doloženo:** API přijme doslovný řetězec jako jméno osoby a zapíše pod něj dovolenou (Console, 14. 11. 2026, 13:20: *„Zapsáno 1 dní dovolené pro osobu {{PersonID}}.“*). Nové, dosud nepoužité jméno se chová jako čistá osoba (143 / 17).

**Odvozeno `[HYPOTÉZA]`:** běh v 12:32 proběhl nad jménem `{{PersonId}}`, které už mělo vadných 17 dnů zapsaných z dřívějších pokusů. Proto API vrátilo prázdné `MarkedDays` a testy svátků prošly. Kontrolní den 20. 8. pro toto jméno zřejmě zapsán nebyl (kontrolní test prošel), zapsal se až při tomto běhu a proto zčervenal v 13:10. Odpovědi z běhu v 12:32 jsem přímo neviděl. Vyplývá to z toho, že čisté jméno dává 17 červených.

### Přehled a srovnání testovacích běhů

| Čas (14. 11. 2026) | Co Postman poslal | Stav osoby v DB | Výsledek (zelené / červené) | Vysvětlení chování |
| :--- | :--- | :--- | :--- | :--- |
| **12:32** | `{{PersonId}}` *(doloženo Console)* | 17 vadných dnů pravděpodobně už zapsáno, 20. 8. ne *[HYPOTÉZA]* | [**160 / 0**](screenshots/DDT_Vacation_PersonId_run_withoutErr_1232.png) | 17 vadných svátků už bylo pro toto jméno zapsáno, API vrátilo prázdné `MarkedDays: []` a svátky prošly. Kontrolní den 20. 8. se zapsal až při tomto běhu, proto prošel také. Všech 160 testů zelených. |
| **12:56** | `RP260` *(správná proměnná)* | Čistá osoba *(předpoklad: dosud nepoužitá)* | [**143 / 17**](screenshots/DDT_Vacation_personId_run_17_Errs_1256.png) | **Správný výsledek.** Test odhalil všech 17 záměrných vad API (např. svátky `2028-12-25` a `2028-12-26` se chybně zapsaly). |
| **13:10** | `{{PersonId}}` *(opakovaný běh)* | Již existující *(vč. 20. 8. z běhu 12:32)* | [**159 / 1**](screenshots/DDT_Vacation_PersonId_run_1_Err_1310.png) | Zčervenal pouze kontrolní pracovní den (20. 8.), protože pro jméno `{{PersonId}}` už byl zapsaný z dřívějška. |
| **13:20** | `{{PersonID}}` *(jiný překlep)* | Nová „pseudo-osoba“ | [**143 / 17**](screenshots/DDT_Vacation_PersonID_run_17Errors_1320.png) | Nový neexistující řetězec API založilo jako čistou osobu a chovalo se stejně jako u platného ID. [Doloženo Console:](screenshots/DDT_Vacation_Run_Concole_PersonID_1320.png) *„Zapsáno 1 dní dovolené pro osobu {{PersonID}}.“* |

> **Zjištěné poznatky:** Výsledek testu závisí na stavu databáze – rozbitá proměnná prošla bez chyby (160/0) pravděpodobně proto, že pro daný řetězec už byla data v databázi zapsaná *[HYPOTÉZA]*. Ani kontrolní řádek s pracovním dnem (20. 8.) není spolehlivou ochranou proti rozbité proměnné, pokud test neběží nad čistými daty.

---

## 4. Řešení: Automatický „hlídač“ nevyhodnocených proměnných
Aby test nespoléhal jen na stav dat a okamžitě odhalil jakoukoliv nevyhodnocenou proměnnou `{{...}}` v těle nebo URL požadavku, doplnil jsem (s pomocí AI, `/AI`) do záložky **Scripts** dvoufázovou kontrolu.

*(Poznámka z vývoje: Samotné volání `pm.variables.replaceIn(...)` v Pre-request skriptu nestačí, protože výsledek jen vrátí, ale nikam neuloží ani neověří. Proto je nutné výsledek uložit do lokální proměnné a vyhodnotit v Post-response testu.)*

**Původ `/AI` a oprava:** první verze od AI kontrolovala natvrdo napsanou proměnnou `{{personId}}`, ne skutečné tělo požadavku, a jen vypisovala do Console. Při rozbitém těle (`{{PersonID}}`) by tedy hlásila `OK`, takže by sama byla falešně zelená (zjištěno rozborem, tuto první verzi jsem sabotáží nespustil). Verze níže kontroluje skutečné tělo a URL a výsledek vyhodnocuje test.

**Rozsah hlídače:** kontroluje jen `raw` tělo a URL (včetně query). Nehlídá hlavičky, autorizaci ani jiné typy těla (např. form-data).

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
Asserce ověří, že kontrola proběhla a dopadla stavem `"OK"`. Díky tomu hlídač **selhává bezpečně (fail-safe)**. Ověřeno pro vypnutí pre-requestu přes `return;` (sekce 5): test neskončí zeleně, ale spadne na chybu `expected undefined to equal 'OK'`. Smazání pre-requestu nebo přejmenování proměnné by mělo dát totéž (`undefined`), ale neověřeno. Hlídač se naopak potichu vyřadí smazáním samotného testu v záložce Tests.

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
Nasazení hlídače rozšířilo sadu ze 160 na **200 testů** (40 iterací × 5 testů). Funkčnost jsem ověřil řízenou sabotáží vstupů i samotného skriptu:

| Scénář ověření | Výsledek | Co tento běh dokazuje |
| :--- | :--- | :--- |
| **1. Správná proměnná `{{personId}}` (osoba `RP279`), hlídač zapnutý** | **200 testů, 17 červených** | Hlídač je zelený (`Console: OK`), test spolehlivě zachytil 17 záměrných vad API. |
| **2. Rozbitá proměnná `{{PersonId}}`, hlídač zapnutý** (jméno použité už v dřívějších bězích) | **200 testů, 41 červených** | Hlídač zčervenal ve všech 40 iteracích a v hlášce testu je přesné tělo požadavku. Zbývající 1 chyba je kontrolní den 20. 8. (již zapsaný z dřívějška) *[HYPOTÉZA]*. |
| **3. Správná proměnná, hlídač vypnutý (`return;`)**, čistá osoba (projevilo se 17 vad API) | **200 testů, 57 červených** | Hlídač **selhává bezpečně** (40× chyba `expected undefined to equal 'OK'` + 17 vad API). Vypnutí pre-requestu hlídač neukryje (ověřeno jen pro `return;`). |

**Stejný test, stejné datum, jiný výsledek:** test svátku `2028-12-25` skončil při správné osobě červeně (běh 12:56) a při rozbité proměnné zeleně, zatímco hlídač byl ve stejné iteraci červený (běh 18:54).

---

## 6. Otevřená otázka na systémového analytika
Vzhledem k tomu, že při testování nebyla k dispozici kompletní specifikace API, nehlásil jsem chování serveru rovnou jako chybu, ale připravil jsem jej jako dotaz k vyjasnění validace vstupů:

> **Otázka na analytika:** *Má API přijmout jakýkoliv libovolný textový řetězec jako `personId` (např. neexistující ID nebo řetězec `"{{PersonId}}"`), založit ho, odpovědět `200 OK` a zapsat mu dovolenou? Neměla by na vstupu probíhat validace formátu či existence zaměstnance v číselníku, a v případě neplatného vstupu vracet klientskou chybu `4xx` (např. `400 Bad Request` nebo `404 Not Found`)?*

*Doložení: odpověď „Zapsáno 1 dní dovolené pro osobu {{PersonID}}.“ (Console, 14. 11. 2026, 13:20).*

---

## 7. Poznatky pro praxi
* **Izolace testovacích dat je nutnost:** Stejný vstup dává při opakování jiný výsledek podle stavu databáze. Každý běh DDT sady proto musí používat **novou, čistou testovací osobu** (např. `RP261`, `RP262`, `RP279`), nebo po sobě data uklízet, pokud to API umožňuje (možnost úklidu nebyla ověřena).
* **Testovací data zůstávají v API:** sabotáže zanechaly záznamy pod jmény `{{PersonId}}` a `{{PersonID}}`.
* **Zelený test ještě neznamená funkční aplikaci:** Vždy je nutné ověřit, že testy dokážou selhat ve chvíli, kdy selhat mají (kontrola proti známým chybám), a že asserce ověřují správný důvod úspěchu.
* **Fail-safe přístup u pomocných skriptů:** Kontroly v testech musí být navržené tak, aby jejich případné vypnutí nebo rozbití vedlo k červenému výsledku, nikoliv k falešné zelené.
