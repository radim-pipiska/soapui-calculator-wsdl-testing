# Integrační testování: Návrh odpovědí mocku platební služby

Tento dokument obsahuje návrh chování mock serveru pro platební službu (endpoint `POST /payments`) a definici očekávaných reakcí objednávkového systému. Slouží jako podklad pro vývoj, testování a diskuzi s analytikem.

## Souhrnná tabulka testovacích scénářů

| Odpověď mocku | Co očekávám od objednávky | Zdroj |
| :--- | :--- | :--- |
| **200 OK** + `{"status":"PAID"}` | Objednávka přejde do stavu „Zaplaceno“ a spustí se expedice. | **Specifikace** (pro HTTP a JSON) / **Předpoklad** (pro chování objednávky) |
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

### Architektura požadavků
Kolekce obsahuje dva nezávislé `POST /payments` requesty, které sdílejí stejných 5 uložených příkladů (Examples: `Scenario_PAID`, `Scenario_DECLINED`, `Scenario_500`, `Scenario_Empty`, `Scenario_Timeout`), ale liší se způsobem jejich výběru:

1. **`Zpracovat platbu (Sequential)`**
   * **Účel:** Deterministické testování přesného pořadí kroků.
   * **Princip:** Využívá proměnnou `sequential_index`. Při každém spuštění inkrementuje index a přes hlavičku `x-mock-response-name` si vyžádá konkrétní příklad. 
   * **Izolace:** Pořadí kroků začíná vždy od indexu `0` (úspěšná platba) bez ohledu na to, zda byl předtím volán náhodný režim.

2. **`Zpracovat platbu (Randomized)`**
   * **Účel:** Testování robustnosti a odolnosti systému proti náhodným chybám.
   * **Princip:** Pomocí `Math.floor(Math.random())` náhodně vybere jeden z 5 scénářů a předá ho mock serveru. Neovlivňuje stav sekvenčního čítače.

### Automatizované testy (Záložka Tests)
Oba požadavky sdílejí identický testovací skript pro automatické vyhodnocení výsledků (např. v CI/CD nebo Runneru). Skript dynamicky čte aktuálně zvolený scénář a provádí následující ověření:
* **Validace HTTP Status kódu:** Kontroluje shodu s očekávaným kódem (200 pro úspěch a prázdné tělo, 402 pro odmítnutí, 500 pro vnitřní chybu).
* **Strukturální validace (JSON):** U obchodních stavů ověřuje existenci klíče `status` a jeho hodnotu (`PAID` / `DECLINED`). U chybového stavu ověřuje přítomnost klíče `error`.
* **Kontrola prázdného těla:** U scénáře `Scenario_Empty` explicitně testuje, že délka textu odpovědi je přesně `0` bajtů, čímž předchází chybám při parsování neexistujícího JSONu.
