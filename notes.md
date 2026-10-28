# Poznámky: SoapUI a Calculator (WSDL, XML, XPath, aserce)

Testováno v říjnu 2026 na veřejné demo službě třetí strany:
`http://www.dneonline.com/calculator.asmx?WSDL`

Nástroj: SoapUI 5.10.0 (podle záhlaví okna).

Stav: **rozpracováno**. Body označené `[OVĚŘIT]` zatím nemám potvrzené.

## 1. Služba

- Endpoint: `http://www.dneonline.com/calculator.asmx`
- Operace: Add, Subtract, Multiply, Divide
- Namespace služby (`targetNamespace`): `http://tempuri.org/`
- Namespace SOAP 1.1 obálky: `http://schemas.xmlsoap.org/soap/envelope/`
- SOAPAction pro Add: `http://tempuri.org/Add` (přečteno z WSDL)
- Bindingy: dva, SOAP 1.1 a SOAP 1.2 `[DOPLNIT: názvy bindingů z WSDL]`
- SOAP 1.2 přenáší action jako parametr `action` v hlavičce Content-Type, ne jako samostatnou hlavičku SOAPAction `[OVĚŘIT v requestu ve SoapUI]`
- Vstupy `intA`, `intB`: `s:int` (xsd:int, 32bitové celé číslo se znaménkem, rozsah -2 147 483 648 až 2 147 483 647), `minOccurs="1"`, `maxOccurs="1"`, tedy povinné prvky

## 2. Add (7 + 5)

- Odpověď: `<AddResult>12</AddResult>` uvnitř `<AddResponse xmlns="http://tempuri.org/">`
- Aserce: SOAP Response (VALID), Schema Compliance (VALID), XPath Match (VALID)

Funkční XPath s deklarací:

```
declare namespace soap='http://schemas.xmlsoap.org/soap/envelope/';
declare namespace ns1='http://tempuri.org/';
//ns1:AddResult
```

Očekávaný výsledek: `12`

## 3. Divide (2 / 0)

Pozorování (bez hodnocení, specifikaci chování pro dělení nulou nemám):

- HTTP stav: `500 Internal Server Error`
- `faultcode`: `soap:Server`
- `faultstring`: `System.Web.Services.Protocols.SoapException: Server was unable to process request. ---> System.OverflowException: Arithmetic operation resulted in an overflow.` následovaný stack trace s cestou na serveru
- `detail`: prázdný (`<detail/>`)
- Zajímavost: Fault obsahuje interní výjimku a cestu k souboru na serveru. Zapsáno jako pozorování, ne jako potvrzená vada.

### Aserce na Divide (výchozí stav, 2 / 0)

| Aserce | Nastavení | Výsledek |
|---|---|---|
| SOAP Response | | VALID |
| Valid HTTP Status Codes | `500` | VALID |
| SOAP Fault | | VALID |
| XPath Match | `declare namespace soap='http://schemas.xmlsoap.org/soap/envelope/'; //soap:Fault/faultcode`, očekáváno `soap:Server` | VALID |
| Schema Compliance | | VALID |

Poznámky:

- Všech pět je zelených i na chybové odpovědi. SOAP Response a Schema Compliance tedy neříkají, že volání uspělo, jen že odpověď je platná SOAP zpráva `[HYPOTÉZA: Fault je platná zpráva podle schématu obálky, neověřeno]`.
- Tato sada **pinuje pozorované chování**, ne specifikaci (specifikaci pro dělení nulou nemám). HTTP 500 pro Fault vyplývá ze SOAP 1.1, ale `soap:Server` je jen pozorování. Pokud se služba opraví (např. na `soap:Client`), sada zčervená, což je správně: signalizuje změnu chování.

## 3b. Add: hranice typu `int`

Vstupy vycházejí z XSD (`s:int`, maximum 2147483647).

| Vstup | Výsledek |
|---|---|
| 2147483646 + 1 | `AddResult` = `2147483647`, bez Faultu, HTTP 200 |
| 2147483647 + 1 | HTTP 500, Fault `soap:Server`, `System.OverflowException: Arithmetic operation resulted in an overflow.` v `Calculator.Add(Int32 intA, Int32 intB)`, řádek 7 |

Aserce (dva samostatné requesty, oba ve výchozím stavu zelené):

| Request | Vstup | Aserce |
|---|---|---|
| `Add - max valid` | 2147483646 + 1 | Valid HTTP Status Codes `[DOPLNIT hodnotu]`, Not SOAP Fault, XPath Match na `AddResult` = `2147483647` |
| `Add - overflow` | 2147483647 + 1 | Valid HTTP Status Codes (500), SOAP Fault, XPath Match na `faultcode` = `soap:Server` |

Pozorování (specifikaci chování pro přetečení nemám, nehodnotím jako vadu):

- Součet přesahující rozsah `int` nevrátí zalomenou (záporná) hodnotu, ale Fault.
- Hypotéza (neověřeno): služba počítá s kontrolou přetečení.
- Tip před spuštěním byl chybný: čekal jsem výsledek `2147483648`, ale ten se do typu `int` nevejde. Tip musí respektovat typ, ne jen matematiku.
- `OverflowException` vrací i Divide (2 / 0). Text výjimky proto nerozliší příčinu chyby, v `faultstring` se liší jen název metody a řádek, což je detail implementace.

## 4. Pravidlo o namespace

- Namespace je text, který určuje, komu element patří. Prefix (`tem:`, `ns1:`) je jen přezdívka.
- `<tem:Add xmlns:tem="http://tempuri.org/">` a `<Add xmlns="http://tempuri.org/">` jsou stejný namespace.
- Rozhoduje přesný text URI (včetně lomítka na konci).
- XPath 1.0 nemá výchozí namespace: `//AddResult` hledá element **bez** namespace a nenajde nic.

## 5. Experimenty (sabotáže)

| # | Co jsem změnil | Odpověď serveru | Výsledek aserce |
|---|---|---|---|
| A | XPath `//AddResult` bez deklarace, očekáváno 12 | 12 | FAILED |
| B | XPath `//ns1:AddResult` s `ns1` = `http://tempuri.org/` | 12 | VALID |
| C | Deklarace `ns1` změněna na `http://tempura.org/` | 12 | FAILED (element v tom namespace není) |
| D | V **requestu** `xmlns:tem` změněno na `http://tempura.org/` | **0** bez chyby | XPath Match FAILED (čekáno 12 nebo 99, přišlo 0) |
| E | Očekávaná hodnota 13 místo 12 | 12 | FAILED |
| F | Očekávaná hodnota `12` plus nový řádek | 12 | FAILED `[OVĚŘIT screenshotem]` |
| G | Divide: Valid HTTP Status Codes změněno z 500 na `200` | Fault, HTTP 500 | FAILED: `Response status code:500 is not in acceptable list of status codes` |
| H | Divide: XPath Match na `faultcode`, očekáváno `soap:Client` | `soap:Server` | FAILED: `XPathContains comparison failed for path [declare namespace soap='http://schemas.xmlsoap.org/soap/envelope/';//soap:Fault/faultcode], expecting [soap:Client], actual was [soap:Server]` |
| I | Divide: aserce SOAP Fault nahrazena aserci Not SOAP Fault | Fault | FAILED: `Response is a SOAP Fault` |
| J | Klon `Add - overflow` (2147483647 + 1) zdědil XPath na `//ns1:AddResult` | Fault, HTTP 500 | FAILED: `XPathContains assertion failed for path [...//ns1:AddResult] : Exception:Missing content for xpath [...] in Response` |
| K | Add 2147483646 + 1, očekáváno `12` | 2147483647 | FAILED: `XPathContains comparison failed for path [...//ns1:AddResult], expecting [12], actual was [2147483647]` |
| L | `Add - overflow` s aserci na 500, ale validní vstup 2147483646 + 1 | 2147483647, HTTP 200 | Valid HTTP Status Codes FAILED: `Response status code:200 is not in acceptable list of status codes` |
| M | Stejný vstup, aserce SOAP Fault | `AddResult` bez Faultu | SOAP Fault FAILED: `Response is not a SOAP Fault` |
| N | `Add - max valid`, očekáváno `2147483648` | 2147483647 | FAILED: `XPathContains comparison failed for path [declare namespace soap='http://schemas.xmlsoap.org/soap/envelope/'; declare namespace ns1='http://tempuri.org/'; //ns1:AddResult], expecting [2147483648], actual was [2147483647]` |
| O | `Add - overflow`, XPath Match na `faultcode`, očekáváno `soap:Client` | `soap:Server` | FAILED: `XPathContains comparison failed for path [declare namespace soap='http://schemas.xmlsoap.org/soap/envelope/'; //soap:Fault/faultcode], expecting [soap:Client], actual was [soap:Server]` |
| P | Divide 2 / 0, aserce na `faultstring` od AI (CZ v6), Allow Wildcards zaškrtnuto, Expected `*Server was unable to process request.*System.OverflowException: Arithmetic operation resulted in an overflow.*` | Fault, `faultstring` začíná `System.Web.Services.Protocols.SoapException: Server was unable to process request. ---> System.OverflowException: Arithmetic operation resulted in an overflow.`, pak nový řádek a `at Calculator.Divide(...)` | **FAILED už ve výchozím stavu**: `XPathContains comparison failed for path [...//soap:Fault/faultstring], expecting [*...overflow.*], actual was [System.Web.Services.Protocols.SoapException: ...]` (zkráceno) |
| Q | Totéž, Expected změněno na `*...System.DivideByZeroException: Arithmetic operation resulted in an overflow.*` | stejná odpověď | FAILED stejnou hláškou. Nic nedokazuje, protože aserce byla červená už před sabotáží |
| R | Divide 2 / 2, aserce na `faultstring` | úspěšná odpověď bez Faultu | FAILED: `XPathContains assertion failed for path [...//soap:Fault/faultstring] : Exception:Missing content for xpath [...] in Response` |
| S | Divide 2 / 2 (platný vstup), aserce pro Fault (Valid HTTP Status Codes, XPath na `faultcode`) | HTTP 200, `<DivideResponse xmlns="http://tempuri.org/"><DivideResult>1</DivideResult></DivideResponse>` | Valid HTTP Status Codes FAILED: `Response status code:200 is not in acceptable list of status codes`. XPath Match FAILED: `Exception:Missing content for xpath [declare namespace soap='http://schemas.xmlsoap.org/soap/envelope/';//soap:Fault/faultcode]` |
| T | Test wildcardu: Expected `soap:*` (Allow Wildcards) na XPath `faultstring` (měl být `faultcode`) | Fault | FAILED: `expecting [soap:*], actual was [System.Web.Services.Protocols.SoapException: ...]`. Nic nedokazuje, `faultstring` nezačíná `soap:`. Test zopakovat na `faultcode` |
| U | Divide 2 / 0, aserce Contains s obsahem `System.OverflowException` | Fault | VALID (zelená ve výchozím stavu) |
| V | Divide 2 / 0, XPath `//soap:Envelope/soap:Body/soap:Fault/faultcode`, Expected `soap:*`, Allow Wildcards | Fault | VALID (wildcard funguje na jednořádkové hodnotě) |
| W | Divide 2 / 0, XPath `normalize-space(//soap:Fault/faultstring)` (jeden řádek), Expected `*Server was unable to process request.*System.OverflowException: Arithmetic operation resulted in an overflow.*`, Allow Wildcards | Fault | FAILED i na jednom řádku: `expecting [*...overflow.*], actual was [System.Web.Services.Protocols.SoapException: Server was unable to process request. ---> System.OverflowException: Arithmetic operation resulted in an overflow. at Calculator.Divide(Int32 intA, Int32 intB) in G:\...:line 19 --- End of inner exception stack trace ---]`. Hypotéza o novém řádku vyvrácena, příčina neznámá |
| X | Divide 2 / 0, aserce Contains s obsahem `System.DivideByZeroException` | Fault | FAILED: `Missing token [System.DivideByZeroException] in Response` |
| Y | `Divide - request` 2 / 2 (happy path), XPath `//ns1:DivideResult`, očekáváno `2` místo `1` | `DivideResult` = 1 | FAILED: `XPathContains comparison failed for path [declare namespace soap='http://schemas.xmlsoap.org/soap/envelope/'; declare namespace ns1='http://tempuri.org/'; //ns1:DivideResult], expecting [2], actual was [1]`. Výchozí stav před sabotáží: 5 aserací zelených (SOAP Response, Valid HTTP Status Codes, Schema Compliance, Not SOAP Fault, XPath Match) |
| Z | `Divide - request` 7 / 2 (bez specifikace, pozorování) | `DivideResult` = **4**, bez Faultu | Tip předem 4 (zaokrouhlení 3,5) byl správný. Výsledek není celočíselné dělení s oříznutím (to by dalo 3). Možné vysvětlení: zaokrouhlení nebo zaokrouhlení nahoru `[HYPOTÉZA]` |
| AA | Divide 2 / 0, wildcard na `normalize-space(//soap:Fault/faultstring)`: A) `System.Web.Services.Protocols.SoapException*`, B) `*System.OverflowException*`, C) `*Server was unable to process request.*System.OverflowException*` | Fault | **Všechny tři FAILED** (tip A selže: správně, B projde: chybně, C selže: správně). Přitom `soap:*` na `faultcode` funguje. Hypotéza o více hvězdičkách i o novém řádku je vyvrácena, příčina neznámá. Podezření: tečka ve výrazu `[HYPOTÉZA]` |
| AB | Divide 2 / 0, XPath `contains(normalize-space(//soap:Fault/faultstring), 'System.OverflowException')`, Expected `true` | Fault | VALID (zelená ve výchozím stavu, sabotáž zatím neproběhla) |
| AC | Divide 2 / 0, `faultcode` s `soap:*`: změněna deklarace prefixu na `xsoap`, ale zbytek cesty zůstal `soap:Body/soap:Fault` | Fault | FAILED. Pravděpodobně chyba výrazu (nedeklarovaný prefix `soap`), ne neshoda hodnoty `[OVĚŘIT celou hlášku]`. Sabotáž je potřeba zopakovat změnou jen Expected na `xsoap:*` |

Rozdíl mezi hláškami: `Missing content` znamená, že element v odpovědi vůbec není (zde Fault), `comparison failed ... actual was` znamená, že element je, ale má jinou hodnotu.

Závěry:

- **D:** služba špatný namespace v requestu **tiše přijala** a vrátila 0. SOAP Response a Schema Compliance zůstaly zelené, chybu zachytila jen aserce na hodnotu.
- **F:** SoapUI porovnává text přesně, včetně mezer a konců řádků.
- **C vs. D:** změna v deklaraci aserce nemění odpověď serveru, změna v requestu ano.

Hypotéza k D (nepotvrzeno): server nenalezené `intA` a `intB` vzal jako výchozí 0 a spočítal 0 + 0.

## 6. Kontrola výstupu AI

- AI tvrdila, že HTTP 500 je v SOAP "univerzální chyba". Nepřesné: SOAP 1.1 předepisuje 500 pro každý Fault (včetně chyb klienta), ale 500 může přijít i bez Faultu (např. HTML stránka proxy). Proto kontroluji, že tělo je skutečně `<soap:Fault>`.
- `//*[local-name()='AddResult']` ignoruje namespace, takže nedokazuje, že je namespace správně. Pro hlídání kontraktu používám deklaraci namespace.
- Při návrhu promptu pro AI jsem měl ve vzoru očekávání `DivideByZero`, ale skutečný Fault obsahuje `System.OverflowException`. Očekávání z domněnky místo z pozorování by dalo zbytečně červenou aserci. Do promptu patří skutečná odpověď a správná URL služby (`http://www.dneonline.com/calculator.asmx`).
- Lekce: u každé aserce vyzkoušet, že umí selhat (hodnota, namespace, vstup) a po sabotáži vrátit výchozí stav.
- Třetí druh červené: aserce s chybně napsaným XPath (`ns1::Fault/faultcode`, špatný prefix) skončí chybou výrazu, ne neshodou s odpovědí. Zelená před sabotáží je proto povinná.
- Prompt pro AI jsem opakovaně psal s chybami (useknutá URI namespace, špatná adresa služby, odpověď z jiné operace, než popisuje scénář). Kopie byla přesná, ale z jiného requestu: přesná kopie neznamená správný zdroj.
- Kontrola výstupu AI (`soapui-divide-by-zero-assertions.md`, prompt CZ v6) proti SoapUI:
  - Hláška při selhání na 2 / 2: AI uvedla `XPath contains no matches`, skutečná hláška je `Exception:Missing content for xpath [...] in Response`. Výstup z EN promptu ji uvedl správně.
  - Aserce na `faultstring` s hvězdičkami (Allow Wildcards zaškrtnuto) byla **červená už ve výchozím stavu** na Divide 2 / 0. Tvrzení AI, že wildcard pohltí konce řádků, se nepotvrdilo. Příčina není nový řádek (vyvráceno normalizací na jeden řádek, viz řádek W), zatím neznámá. Následná sabotáž `DivideByZeroException` proto nic nedokazuje.
  - `DivideResult` a odpověď 200 pro 2 / 2: potvrzeno (HTTP 200, `DivideResult` = 1), AI to ale neoznačila jako předpoklad.
  - Wildcard `soap:*` na `faultcode` funguje (zelená, řádek V). Výraz s více hvězdičkami na `faultstring` selhal i po normalizaci na jeden řádek (řádek W). Hypotéza o novém řádku je vyvrácena, příčina zůstává neznámá.
  - Výstup z EN promptu obsahuje „Prohlášení o předpokladech“, výstup z CZ ne. Pokud oba prompty běžely ve stejné konverzaci, nejsou výsledky nezávislé `[OVĚŘIT]`.

## 6b. Řetězení kroků: TestSuite „Calculator“, TestCase „Chain“

Kroky: `Add_Prvni` (100000 + 23) -> `Property Transfer` -> `Add_Druhy` (intA z přenosu + 7).

Property Transfer:

- Zdroj: `Add_Prvni`, Response: `declare namespace ns1='http://tempuri.org/'; //ns1:AddResult`
- Cíl: `Add_Druhy`, Request: `declare namespace tem='http://tempuri.org/'; //tem:Add/tem:intA`
- Nastavení: Fail transfer on error, Transfer text content, Set null on missing source (zaškrtnuto)

| Situace | Výsledek |
|---|---|
| Správné cesty | TestCase FINISHED, všechny tři kroky OK |
| Cíl `//tem:Add/soap:intA` (prefix `soap` není deklarován) | Krok Property Transfer FAILED, TestCase zastaven (`Cancelling due to failed test step`), krok 3 se nespustil. Zpráva: `net.sf.saxon.trans.XPathException: XPath syntax error at char 1 on line 3 in {\n//tem:Add/soap:intA\n}: Prefix soap has not been declared` |
| Obě pole XPath prázdná (zdroj i cíl) | Krok Property Transfer hlásí OK, ale celý request kroku 3 je přepsán odpovědí kroku 1. Server vrátil `AddResult` = `0` bez Faultu. Krok 3 selhal až na aserci: `[Contains] Missing token [15] in Response` a XPath Match |
| 100000 + 23, pak + 7 | `AddResult` = `100030`, aserce SOAP Response, XPath Match a Contains (`100030`) zelené |
| 200000 + 5, `intA` v kroku 3 předem ručně `-1` | Pokus 1: krok 1 selhal na XPath Match (aserce měla starou očekávanou hodnotu, chyba testu, ne služby). Po opravě očekávání pokus 2: `AddResult` = `200012`, přenos funguje |
| Zdroj `//ns1:AddResultX`, Set null on missing source **nezaškrtnuto** | Krok Property Transfer selže: `PropertyTransferException: Missing match for Source XPath [declare namespace ns1='http://tempuri.org/'; //ns1:AddResultX ]`, TestCase se zastaví, krok 3 se nespustí a jeho request zůstane nezměněný (`intA` = 1). Transfer Log: `[Missing match for Source XPath [...]`; zopakováno čistě 27. 10. |
| Zdroj `//ns1:AddResultX`, Set null on missing source **zaškrtnuto** | V requestu kroku 3 zůstal prázdný `intA` (`<tem:intA/>`). Server vrátil SOAP 1.2 Fault: `soap:Value` = `soap:Sender`, `soap:Text`: `Server was unable to read request. ---> ... System.FormatException: Input string was not in a correct format.` Čistě zopakováno 27. 10. (intA předem 1): Property Transfer **OK** (Transfer Log: `[null]`), krok 3 dostal prázdný `intA` (`<tem:intA/>`) a vrátil stejný Fault. Selhala až aserce XPath Match: `Exception:Missing content for xpath [declare namespace soap='http://www.w3.org/2003/05/soap-envelope'; declare namespace ns1='http://tempuri.org/'; //ns1:AddResult] in Response`. Tip předem „transfer selže“ byl chybný |

Závěry:

- Přenos s prázdnou cestou skončí jako OK, ale zničí request. Chybu zachytily až aserce na hodnotu. Server nesmyslný request tiše přijal (podobně jako případ D se `tempura`).
- Potvrzeno pozorováním: v kroku `Add_Druhy` zůstává `intA` z posledního přenosu až do dalšího přepsání transferem. Vadný nebo vypnutý přenos proto může použít starou hodnotu a test může být falešně zelený.
- Chain používá interface `CalculatorSoap12` (SOAP 1.2, envelope `http://www.w3.org/2003/05/soap-envelope`), dřívější requesty `CalculatorSoap` (SOAP 1.1). XPath s namespace SOAP 1.1 na odpověď 1.2 nic nenajde. Struktura Faultu ve SOAP 1.2 je jiná (potvrzeno pozorováním): `soap:Fault` obsahuje `soap:Code/soap:Value` (zde `soap:Sender`) a `soap:Reason/soap:Text`, ne `faultcode` a `faultstring`. Aserce psané pro SOAP 1.1 (`//soap:Fault/faultcode`) na 1.2 nefungují.
- Při sabotáži zdroje zůstal v requestu kroku 3 poškozený dokument (`<tem:intA/></tem:intA>`, samouzavřený tag a osiřelý koncový tag). Další běh pak hlásil `Error parsing target property [error: The element type "tem:Add" must be terminated by the matching end-tag "</tem:Add>".]`. Tato hláška je zbytek po předchozím běhu nebo ruční úpravě: při čistém opakování 27. 10. se nereprodukovala. Po každé sabotáži vrátit request do platného stavu a ověřit zelený běh dřív, než přijde další sabotáž.
- Set null on missing source mění hlasité selhání (`Missing match for Source XPath`) na tiché: transfer hlásí OK, zapíše `[null]` a request kroku 3 má prázdný `intA` (`<tem:intA/>`). Chybu pak zachytí až server (Fault `soap:Sender`) a aserce na hodnotu. Pro testy preferuji volbu nezaškrtnutou, aby řetěz selhal na správném místě.

## 7. Otevřené

- [x] SOAPAction pro Add ověřit ve WSDL
- [x] Zjistit, zda Schema Compliance a SOAP Response projdou na Faultu (projdou)
- [x] Aserce Valid HTTP Status Codes, SOAP Fault a XPath na `faultcode` na Divide
- [ ] Vrátit aserce na Divide do výchozího zeleného stavu a znovu exportovat projekt
- [ ] Doplnit názvy bindingů z WSDL
- [x] Hranice typu `int` (viz XSD) na Add: 2147483647 + 1
- [x] Klon `Add - overflow`: aserce Valid HTTP Status Codes (500), SOAP Fault a XPath na `faultcode`
- [x] Samostatný request `Add - max valid` (2147483646 + 1) se zelenou asercí na `2147483647`
- [x] HTTP status u 2147483646 + 1 (200)
- [x] Sabotáž XPath Match na `faultcode` u `Add - overflow` (doslovná hláška)
- [x] Chain: čisté opakování sabotáže zdroje (obě varianty Set null)
- [x] Chain: důkaz, že se hodnota opravdu přenáší (200000 + 5 -> 200012)
- [x] Chain: aserce na krok 1
- [x] Aserce na `faultstring` zelená na Divide 2 / 0 (přes `contains()`, sabotáž zbývá)
- [x] Zjistit odpověď Divide 2 / 2 (název elementu, HTTP status)
- [x] Zopakovat test wildcardu na `faultcode` (Expected `soap:*`)
- [x] Sabotáž aserce Contains (`System.DivideByZeroException`)
- [x] Wildcard na `faultstring` nahrazen funkcí `contains()` (zelená). Příčina selhání wildcardů zatím neznámá
- [x] Odstranit sabotážní kopii aserce Contains (DivideByZeroException) před exportem
- [ ] Sabotáž aserce `soap:*` na `faultcode`: zopakovat změnou jen Expected na `xsoap:*` (původní pokus měl rozbitý výraz)
- [ ] Sabotáž aserce s `contains()` (např. `System.DivideByZeroException`), tip předem na hlášku
- [ ] Přejmenovat aserci `soap:faultstring Wildcard` (už nepoužívá wildcard) a odškrtnout Allow Wildcards
- [ ] Vrátit `Divide - request` na 2 / 2 a Expected `1` (po pokusech zůstalo 7 / 2 a očekávané 2)
- [ ] Zjistit příčinu selhání wildcardů: testovat bez tečky (`*unable*`, `System*`)
- [x] Divide: happy path (2 / 2 -> 1) vytvořen, 5 zelených aserací; `Divide by Zero` je samostatný krok
- [x] Chain: doplnit celou hlášku Saxon z kroku Property Transfer
- [ ] Zkontrolovat výstup AI (`soapui-divide-by-zero-assertions.md`, vygenerováno promptem CZ v6) proti skutečnému SoapUI
- [ ] Doplnit hodnotu Valid HTTP Status Codes u `Add - max valid`
- [ ] Doplnit screenshoty do `screenshots/`
