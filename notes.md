# Poznámky: SoapUI a Calculator (WSDL, XML, XPath, aserce)

Testováno v říjnu 2026 na veřejné demo službě třetí strany:
`http://www.dneonline.com/calculator.asmx?WSDL`

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

## 7. Otevřené

- [x] SOAPAction pro Add ověřit ve WSDL
- [x] Zjistit, zda Schema Compliance a SOAP Response projdou na Faultu (projdou)
- [x] Aserce Valid HTTP Status Codes, SOAP Fault a XPath na `faultcode` na Divide
- [ ] Vrátit aserce na Divide do výchozího zeleného stavu a znovu exportovat projekt
- [ ] Doplnit názvy bindingů z WSDL
- [ ] Hranice typu `int` (viz XSD) na Add: 2147483647 + 1
- [ ] Doplnit screenshoty do `screenshots/`
