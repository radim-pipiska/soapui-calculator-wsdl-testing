|      | REST | SOAP | messaging |
| :--- | :--- | :--- | :--- |
| Kontrakt (kde je popsaný, jak se jmenuje) | OpenAPI (Swagger) | WSDL + XSD | AsyncAPI |
| Formát zprávy | JSON | XML | JSON |
| Jak se pozná úspěch a jak chyba | HTTP 200; HTTP 400, 500 | Úspěch: HTTP 200 + validní JSON, aserce odpovídající business logice; chyba: faultcode soap:Client / soap:Server | DLQ |
| Co test kromě statusu musí ověřit | JSON | XPath Match | log |
| Jedna past z tvé vlastní zkušenosti v těchto týdnech | Divide intB "" | 12+řádek v Xpatch Match |  |
