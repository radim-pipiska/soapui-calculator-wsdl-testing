
**1. Jak koncept asynchronní komunikace vysvětlit juniorovi?**

Představ si rozdíl mezi nákupem v kamenné samoobsluze a na e-shopu. V samoobsluze zboží vybereš, hned zaplatíš u pokladny a odcházíš s nákupem (synchronní proces – čekáš na dokončení). Na e-shopu zboží objednáš, okamžitě dostaneš potvrzení o přijetí objednávky a mezitím na pozadí běží X dalších transakcí (ověření skladu, balení, expedice), zatímco ty se věnuješ jiné práci.
Pro nás jako testery je klíčová tato analogie v API:
- HTTP 202 Accepted: E-shop ti poslal e-mail „Objednávka přijata“. Systém potvrdil, že požadavek je validní a začal na něm pracovat, ale výsledek ještě neznáš.
- Konečný stav (např. HTTP 200 s detailem doručení): Kurýr ti předal balíček do ruky. Úloha byla úspěšně dokončena.

**2. Jak používat AI při psaní aserací pro asynchronní scénáře bez pasti slepé důvěry?**

Základem je předat AI přesný kontext: definovat popis API, uvést, že jde o asynchronní komunikaci, a dodat reálné příklady requestu a response (včetně ošetření stavů u následného GET dotazu).
I s dobrým kontextem ale musíme kontrolovat, zda si AI nezačala vymýšlet:
- Pozor na halucinace polí a stavů: Pokud AI ve specifikaci nenajde přesný název pole nebo stavu (např. zda má konečný stav hodnotu DELIVERED, COMPLETED nebo FINISHED), s klidem si domyslí vlastní validní řetězec, který sice vypadá logicky, ale aplikace ho nepoužívá. Vždy zkontroluj, zda vygenerované aserace sedí na exaktní klíče z tvé dokumentace.
- Ověření selháním (Mutation testing / Red-Green test): Nikdy nevěř testu, který jsi neviděl spadnout. Úmyslně v kódu nebo v mocku změň očekávanou hodnotu (např. změň aseraci na neexistující stav FAILED_TEST) a ověř, že asynchronní testovací aserace skutečně selže a nahlásí chybu. Pokud test projde i s nesmyslnou hodnotou, je špatně napsaný (např. kvůli špatně nastavenému čekání v asynchronní smyčce).
