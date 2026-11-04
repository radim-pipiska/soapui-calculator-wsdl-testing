
# Testování asynchronní komunikace a princip Pollingu
Shrnutí osvědčených postupů pro QA testery při ověřování asynchronních scénářů a integračních testů REST API.

## 1. Jak koncept asynchronní komunikace vysvětlit juniorovi?

**Představ si rozdíl mezi nákupem v kamenné samoobsluze a na e-shopu.** 
* **Samoobsluha (Synchronní proces):** Zboží vybereš, hned zaplatíš u pokladny a odcházíš s nákupem domů. Musíš počkat, než proces kompletně skončí.
* **E-shop (Asynchronní proces):** Zboží objednáš, okamžitě dostaneš potvrzení o přijetí objednávky a můžeš jít dělat cokoliv jiného. Mezitím na pozadí běží X dalších transakcí (ověření skladu, doprava z jiného skladu, balení, expedice) a ty jen čekáš na kurýra.

V reálném API tomuto chování odpovídá tato dvojice stavů:
* **HTTP 202 Accepted:** E-shop ti poslal e-mail *„Objednávka přijata“*. Systém potvrdil, že požadavek přijal.
* **Konečný stav (např. HTTP 200 s detailem doručení):** Kurýr ti předal balíček do ruky. Úloha byla úspěšně dokončena.

## 2. Jak používat AI při psaní aserací bez pasti slepé důvěry?

Základem je předat AI přesný kontext: definovat popis API, uvést, že jde o asynchronní komunikaci, a dodat reálné příklady requestu a response (včetně ošetření stavů u následného GET dotazu). 

I s dobrým kontextem ale musíme kontrolovat, zda si AI nezačala vymýšlet:
* **Pozor na halucinace polí a stavů:** Pokud AI ve specifikaci nenajde přesný název pole nebo stavu (např. zda má konečný stav hodnotu `DELIVERED`, `COMPLETED` nebo `FINISHED`), domyslí si vlastní validní řetězec. Vždy zkontroluj, zda vygenerované aserace sedí na exaktní klíče z tvé dokumentace.
* **Ověření selháním (Red-Green test):** Nikdy nevěř testu, který jsi neviděl spadnout. Úmyslně v kódu nebo v mocku změň očekávanou hodnotu (např. změň aseraci na neexistující stav `FAILED_TEST`) a ověř, že asynchronní testovací aserace skutečně selže. Pokud test projde i s nesmyslnou hodnotou, je špatně napsaný.

## 3. Princip Pollingu (Čekání na výsledek)

Místo nespolehlivého čekání na pevnou pauzu (např. natvrdo nastavený spánek na 5 sekund) se **ptáme systému opakovaně v pravidelných intervalech s nastaveným horním limitem**. Funguje to jako sledování zásilky u kurýra – průběžně kontroluješ stav a vzdáváš to až po vypršení maximálního času nebo počtu pokusů.

Při každém ukončení smyčky (úspěchu i selhání) je nutné **vždy zalogovat**: 
* Korelační ID
* Poslední známý stav
* Počet spotřebovaných pokusů

Bez těchto informací se selhání v logách nedá vyšetřit.

### Tři konce asynchronní smyčky

Smyčka opakovaných GET dotazů na stav objednávky musí končit přesně **třemi způsoby**:

1. **Očekávaný konečný stav (`COMPLETED`)** $\rightarrow$ Smyčka úspěšně končí, následuje aserce na správný výsledek.
2. **Chybový konečný stav (`FAILED`)** $\rightarrow$ Smyčka se okamžitě zastaví. Čekat dál nemá smysl, test ihned selže (zčervená), protože objednávka se nezpracovala.
3. **Vyčerpání limitu pokusů** $\rightarrow$ Stav je i po limitu stále průběžný (`PENDING` nebo `PROCESSING`). Smyčka končí a test selže s hláškou *„Nedokončeno v limitu“*.

*Poznámka: Pokud systém vrátí jakýkoliv **neznámý stav** (mimo specifikované čtyři), smyčka musí okamžitě skončit a test spadnout, aby se netočil donekonečna.*

### Ověření větví pomocí sabotáží (Mocking)

Abychom ověřili, že náš testovací skript správně reaguje na chování systému, musíme nasadit trojici sabotážních mocků:

| Sabotážní scénář (Mock) | Co testuje a ověřuje | Očekávaný výsledek v logu / hláška |
| :--- | :--- | :--- |
| **1. Věčný stav `PROCESSING`** | Prověří hlídače limitu pokusů (že test nezůstane viset navždy). | **Červený test:** „Nedokončeno v limitu“ *(+ ID a počet pokusů)* |
| **2. Okamžitý stav `FAILED`** | Prověří, že test nezůstane zelený, když proces v aplikaci selže. | **Červený test:** „Objednávka selhala ve stavu FAILED“ |
| **3. Neočekávaný stav (např. `UNKNOWN`)** | Prověří hlídače neznámých stavů stojících mimo specifikaci. | **Červený test:** „Detekován neznámý stav: UNKNOWN“ |
