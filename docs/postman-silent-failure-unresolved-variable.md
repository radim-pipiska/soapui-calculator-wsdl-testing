# Případová studie: Skrytá past v podobě case-sensitivity proměnných v Postmanovi

## Kontext a cíl testu
Při datově řízeném testování (DDT – Data-Driven Testing) REST API pro rezervaci dovolených bylo cílem ověřit byznys pravidlo pro filtrování dnů:
* **Pravidlo:** Státní svátky a víkendy (sobota, neděle) se nesmí zapsat do rezervace.
* **Testovací sada:** Celkem 40 iterací (39 státních svátků + 1 kontrolní pracovní den).
* **Očekávané chování:** V testovaném API jsou úmyslně integrované chyby v logice svátků. Správně běžící test měl proto odhalit 17 chybně zapsaných svátků. Dataset obsahuje i Negativní scénář pro zapsání jednoho 1 platného pracovního dne.

## Co se pokazilo (Průběh incidentu)
Testovací sada prošla zdánlivě bez chyb na svátcích, čímž zamaskovala reálné defekty v aplikaci (tzv. *false positive* – falešně pozitivní výsledek).

1. **Překlep v názvu proměnné:** V prostředí (Environment) byla definována proměnná `personId` (camelCase), ale v JSON těle požadavku (Body) bylo použito `{{PersonId}}` (PascalCase).
2. **Chování Postmana:** Názvy proměnných v Postmanovi jsou **case-sensitive** (rozlišují velká a malá písmena). Postman proměnnou `{{PersonId}}` nerozpoznal, nevyhodil žádnou chybu a místo čísla zaměstnance odeslal doslovný text `"{{PersonId}}"` (ověřeno v Postman Console).
3. **Tiché selhání API:** Server přijal neplatný řetězec `"{{PersonId}}"`, vrátil stavový kód `200 OK` a prázdné pole `MarkedDays: []` (nic nezapsal). Protože prázdné pole odpovídalo očekávanému výsledku pro platný svátek, asserce pro všech 39 svátků prošly jako úspěšné.

## Řešení: Automatický „hlídač“ nevyhodnocených proměnných /AI
Aby se podobné tiché chyby způsobené překlepem v `{{...}}` už nemohly opakovat, doplnil jsem do záložky **Scripts** automatickou kontrolu.

### 1. Pre-request Script (Zastavení požadavku před odesláním)
Tento skript zkontroluje tělo požadavku ještě předtím, než opustí Postmana. Pokud v něm zůstane jakýkoliv nevyhodnocený zápis `{{...}}`, skript okamžitě vyhodí chybu a požadavek se ani neodešle.

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

### 2. Post-response Script (Kontrola v rámci testovacích assercí)
Druhá vrstva ochrany v sekci vyhodnocení odpovědi. Hodí se zejména při spouštění testů přes příkazovou řádku (Newman) nebo v CI/CD, kde chceme vidět standardní selhání testu v reportu.

```javascript
pm.test("Všechny proměnné v těle a URL požadavku jsou nahrazeny", function () {
    pm.expect(
        pm.variables.get("local_varsCheck"),
        pm.variables.get("local_varsDetail")
    ).to.equal("OK");
});
```

## Otevřená otázka na systémového analytika
Vzhledem k tomu, že při testování nebyla k dispozici kompletní specifikace API, nehlásil jsem chování serveru rovnou jako chybu, ale formuloval jsem jej jako dotaz k vyjasnění návrhu:

> **Otázka na analytika:** *Jak má API správně reagovat, pokud obdrží neznámé nebo neplatné `personId` (např. neexistující ID zaměstnance nebo chybný datový typ místo čísla)? Nyní server vrací `200 OK` a prázdné pole `MarkedDays: []`, takže tiše nic nezapíše. Neměl by v takovém případě vracet klientskou chybu ze skupiny `4xx` (např. `400 Bad Request` nebo `404 Not Found`), aby klient poznal, že poslal neplatný vstup?*

## Klíčové poznatky pro praxi
* **Zelený test ještě neznamená funkční aplikaci:** Vždy je nutné ověřit, že testy dokážou selhat ve chvíli, kdy selhat mají (kontrola proti známým chybám).
* **Postman Console je základ:** Kontrola reálně odeslaného síťového požadavku nejrychleji odhalí problémy s dosazováním proměnných.
* **Defenzivní skriptování:** Jednoduchá kontrola pomocí regulárního výrazu v Pre-request nebo Post-response skriptu dokáže eliminovat celou třídu lidských chyb při tvorbě API testů.
