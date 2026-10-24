# Poznámky: SoapUI a Calculator (WSDL, XML, XPath, aserce)

Testováno v říjnu 2026 na veřejné demo službě třetí strany:
`http://www.dneonline.com/calculator.asmx?WSDL`

Stav: **rozpracováno**. Body označené `[OVĚŘIT]` zatím nemám potvrzené.

## 1. Služba

- Endpoint: `http://www.dneonline.com/calculator.asmx`
- Operace: Add, Subtract, Multiply, Divide
- Namespace služby (`targetNamespace`): `http://tempuri.org/`
- Namespace SOAP 1.1 obálky: `http://schemas.xmlsoap.org/soap/envelope/`
- SOAPAction pro Add: `[OVĚŘIT]` (čekám `http://tempuri.org/Add`, ověřit ve WSDL v `binding` -> `operation`; WSDL má bindingy pro SOAP 1.1 i 1.2)

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

Závěry:

- **D:** služba špatný namespace v requestu **tiše přijala** a vrátila 0. SOAP Response a Schema Compliance zůstaly zelené, chybu zachytila jen aserce na hodnotu.
- **F:** SoapUI porovnává text přesně, včetně mezer a konců řádků.
- **C vs. D:** změna v deklaraci aserce nemění odpověď serveru, změna v requestu ano.

Hypotéza k D (nepotvrzeno): server nenalezené `intA` a `intB` vzal jako výchozí 0 a spočítal 0 + 0.

## 6. Kontrola výstupu AI

- AI tvrdila, že HTTP 500 je v SOAP "univerzální chyba". Nepřesné: SOAP 1.1 předepisuje 500 pro každý Fault (včetně chyb klienta), ale 500 může přijít i bez Faultu (např. HTML stránka proxy). Proto kontroluji, že tělo je skutečně `<soap:Fault>`.
- `//*[local-name()='AddResult']` ignoruje namespace, takže nedokazuje, že je namespace správně. Pro hlídání kontraktu používám deklaraci namespace.

## 7. Otevřené

- [ ] SOAPAction pro Add ověřit ve WSDL
- [ ] Zjistit, zda Schema Compliance a SOAP Response projdou na Faultu
- [ ] Aserce Valid HTTP Status Codes a SOAP Fault na Divide
- [ ] Doplnit screenshoty do `screenshots/`
