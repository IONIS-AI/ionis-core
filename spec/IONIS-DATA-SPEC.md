# IONIS-AI Data Specification — DRAFT 0.1

> GENERATED from `spec/ionis-spec.json` and ADIF's published `all.json`. Do not edit.

## Part 1 — ADIF 3.1.7

The foundation. ADIF 3.1.7 (Released, 2026-03-22), exactly as published: `all.json` SHA-256 `358f4b086bd68c06c89ea3d45dffd4fd5a4dd38618545e5f8cb84a758ccad52b`, the value adif.org's resource zip carries. Never edited here. Any field we store that ADIF defines uses the definition below.

### 1.1 Data types (28)

| Data type | Indicator | Description | Min | Max | Import-only |
|---|---|---|---|---|---|
| `AwardList` |  | a comma-delimited list of members of the Award enumeration |  |  | true |
| `CreditList` |  | a comma-delimited list where each list item is either: A member of the Credit enumeration. A member of the Credit enumeration followed by a colon and an ampersand-delimited list of members of the QSL_Medium enumeration. For example IOTA,WAS:LOTW&CARD,DXCC:CARD |  |  |  |
| `SponsoredAwardList` |  | a comma-delimited list of members of the Sponsored_Award enumeration |  |  |  |
| `Boolean` | B | if True, the single ASCII character Y or y if False, the single ASCII character N or n |  |  |  |
| `Digit` |  | an ASCII character whose code lies in the range of 48 through 57, inclusive |  |  |  |
| `Integer` |  | a sequence of one or more Digits representing a decimal integer, optionally preceded by a minus sign (ASCII code 45). Leading zeroes are allowed. |  |  |  |
| `Number` | N | a sequence of one or more Digits representing a decimal number, optionally preceded by a minus sign (ASCII code 45) and optionally including a single decimal point (ASCII code 46) |  |  |  |
| `PositiveInteger` |  | an unsigned sequence of one or more Digits representing a decimal integer that has a value greater than 0. Leading zeroes are allowed. | 1 |  |  |
| `Character` |  | an ASCII character whose code lies in the range of 32 through 126, inclusive |  |  |  |
| `IntlCharacter` |  | a Unicode character (encoded with UTF-8) excluding line break CR (code 13) and LF (code 10) characters |  |  |  |
| `Date` | D | 8 Digits representing a UTC date in YYYYMMDD format, where YYYY is a 4-Digit year specifier, where 1930 <= YYYY MM is a 2-Digit month specifier, where 1 <= MM <= 12 [use leading zeroes] DD is a 2-Digit day specifier, where 1 <= DD <= DaysInMonth(MM) [use leading zeroes] |  |  |  |
| `Time` | T | 6 Digits representing a UTC time in HHMMSS format or 4 Digits representing a time in HHMM format, where HH is a 2-Digit hour specifier, where 0 <= HH <= 23 [use leading zeroes] MM is a 2-Digit minute specifier, where 0 <= MM <= 59 [use leading zeroes] SS is a 2-Digit second specifier, where 0 <= SS <= 59 [use leading zeroes] |  |  |  |
| `IOTARefNo` |  | IOTA designator, in format CC-XXX, where CC is a member of the Continent enumeration XXX is the island group designator, where 1 <= XXX <= 999 [use leading zeroes] |  |  |  |
| `String` | S | a sequence of Characters |  |  |  |
| `IntlString` | I | a sequence of International Characters. Fields of type IntlString must only be used in ADX files |  |  |  |
| `MultilineString` | M | a sequence of Characters and line-breaks, where a line break is an ASCII CR (code 13) followed immediately by an ASCII LF (code 10) |  |  |  |
| `IntlMultilineString` | G | a sequence of International Characters and line breaks. Fields of type IntlMultilineString must only be used in ADX files |  |  |  |
| `Enumeration` | E | an explicit list of legal case-insensitive values represented in ASCII set forth in set notation, e.g. {A, B, C, D}, or defined in a table, from which a single value may be selected. |  |  |  |
| `GridSquare` |  | a case-insensitive 2-character, 4-character, 6-character, or 8-character Maidenhead locator. Specific fields impose additional restrictions on the number of characters; see the field descriptions for the allowed numbers of characters. |  |  |  |
| `GridSquareExt` |  | For a 10-character Maidenhead locator, contains characters 9 and 10. For a 12-character Maidenhead locator, contains characters 9, 10, 11 and 12. Characters 9 and 10 are case-insensitive ASCII letters in the range A-X. Characters 11 and 12 are Digits in the range 0-9. |  |  |  |
| `GridSquareList` |  | a comma-delimited list of GridSquare items |  |  |  |
| `Location` | L | a sequence of 11 characters representing a latitude or longitude in XDDD MM.MMM format, where X is a directional Character from the set {E, W, N, S} DDD is a 3-Digit degrees specifier, where 0 <= DDD <= 180 [use leading zeroes] There is a single space character in between DDD and MM.MMM MM.MMM is an unsigned Number minutes specifier with its decimal point in the third position, where 00.000 <= MM.MMM <= 59.999 [use leading and trailing zeroes] |  |  |  |
| `POTARef` |  | a sequence of case-insensitive Characters representing a Parks on the Air park reference in the form xxxx-nnnnn[@yyyyyy] comprising 6 to 17 characters where: xxxx is the POTA national program and is 1 to 4 characters in length, typically the default callsign prefix of the national program (rather than the DX entity) nnnnn represents the unique number within the national program and is either 4 or 5 characters in length (use the exact format listed on the POTA website) yyyyyy **Optional** is the 4 to 6 character ISO 3166-2 code to differentiate which state/province/prefecture/primary administration location the contact represents, in the case that the park reference spans more than one location (such as a trail). Examples of the POTARef Data Type: ReferenceLocation K-5033Golden Hill State Forest K-10000 5-digit park numbers are reserved for future use VE-5082@CA-ABThe Great Trail of Canada (the Canadian Trailway) National Scenic Trail, within Alberta, Canada 8P-0012Chancery Lane Swamp National Park VK-0556Pieman River State Reserve K-4562@US-CAPacific Crest Trail, within California, USA Additional Notes on POTARef: A browsable and searchable list of all park references is available. A complete CSV file is available (generated nightly). For more information, visit the Parks on the Air documentation website. |  |  |  |
| `POTARefList` |  | a comma-delimited list of one or more POTARef items. |  |  |  |
| `SecondarySubdivisionList` |  | a colon-delimited list of two or more members of the Secondary_Administrative_Subdivision enumeration. E.g.: MA,Franklin:MA,Hampshire |  |  |  |
| `SecondaryAdministrativeSubdivisionListAlt` |  | a semicolon (;) delimited, unordered list of one or more members of a Secondary_Administrative_Subdivision_Alt enumeration in the form: enumeration-name:enumeration-code Where there is more than one locality represented by the enumeration-code, they are separated by slash (/) characters. Only one of each enumeration-name valid for the DXCC entity concerned can appear in the list. Examples: <CNTY_ALT:28>NZ_Regions:Hawkes Bay/Wairoa <MY_CNTY_ALT:52>NZ_Islands:North Island;NZ_Regions:Hawkes Bay/Wairoa The first example shows the enumeration-name NZ_Regions with the region Hawkes Bay and the district Wairoa. For the purposes of illustration, the second example includes a non-existent subdivision with two available enumeration-codes, NZ_Islands:North Island and NZ_Islands:South Island. The example shows: the enumeration-name NZ_Islands with the island North Island the enumeration-name NZ_Regions with the region Hawkes Bay and the district Wairoa |  |  |  |
| `SOTARef` |  | a sequence of Characters representing an International SOTA Reference. The sequence comprises: an ITU prefix if applicable, a SOTA subdivision a / Character a SOTA Reference Number Examples: W2/WE-003 G/LD-003 |  |  |  |
| `WWFFRef` |  | a sequence of case-insensitive Characters representing an International WWFF (World Wildlife Flora & Fauna) reference in the form xxFF-nnnn comprising 8 to 11 characters where: xx is the WWFF national program and is 1 to 4 characters in length. FF- is two F characters followed by a dash character. nnnn represents the unique number within the national program and is 4 characters in length with leading zeros. Examples: KFF-4655 3DAFF-0002 |  |  |  |

### 1.2 Fields (186)

| Field | Data type | Enumeration | Description | Min | Max | Import-only |
|---|---|---|---|---|---|---|
| `ADIF_VER` | String |  | Identifies the version of ADIF used in this file in the format X.Y.Z where ● X is an integer designating the ADIF epoch. ● Y is an integer between 0 and 9 designating the major version. ● Z is an integer between 0 and 9 designating the minor version. |  |  |  |
| `CREATED_TIMESTAMP` | String |  | Identifies the UTC date and time that the file was created in the format of 15 characters YYYYMMDD HHMMSS where YYYYMMDD is a Date data type. HHMMSS is a 6 character Time data type. |  |  |  |
| `PROGRAMID` | String |  | Identifies the name of the logger, converter, or utility that created or processed this ADIF content. To help avoid name clashes, the ADIF PROGRAMID Register provides a voluntary list of PROGRAMID values. |  |  |  |
| `PROGRAMVERSION` | String |  | Identifies the version of the logger, converter, or utility that created or processed this ADIF file. |  |  |  |
| `USERDEFn` | String |  | Specifies the name and optional enumeration or range of the nth user-defined field, where n is a positive integer. The name of a user-defined field may not ● be an ADIF Field name. ● contain ○ a comma. ○ a colon. ○ an open-angle-bracket or close-angle-bracket character. ○ an open-curly-bracket or close-curly-bracket character. ● begin or end with a space character. |  |  |  |
| `ADDRESS` | MultilineString |  | the contacted station's complete mailing address: full name, street address, city, postal code, and country |  |  |  |
| `ADDRESS_INTL` | IntlMultilineString |  | the contacted station's complete mailing address: full name, street address, city, postal code, and country |  |  |  |
| `AGE` | Number |  | the contacted station's operator's age in years in the range 0 to 120 (inclusive) | 0 | 120 |  |
| `ALTITUDE` | Number |  | the height of the contacted station in meters relative to Mean Sea Level (MSL). For example 1.5 km is <ALTITUDE:4>1500 and 10.5 m is <ALTITUDE:4>10.5 |  |  |  |
| `ANT_AZ` | Number |  | the logging station's antenna azimuth, in degrees with a value between 0 to 360 (inclusive). Values outside this range are import-only and must be normalized for export (e.g. 370 is exported as 10). True north is 0 degrees with values increasing in a clockwise direction. | 0 | 360 |  |
| `ANT_EL` | Number |  | the logging station's antenna elevation, in degrees with a value between -90 to 90 (inclusive). Values outside this range are import-only and must be normalized for export (e.g. 100 is exported as 80). The horizon is 0 degrees with values increasing as the angle moves in an upward direction. | -90 | 90 |  |
| `ANT_PATH` | Enumeration | Ant_Path | the signal path |  |  |  |
| `ARRL_SECT` | Enumeration | ARRL_Section | the contacted station's ARRL section |  |  |  |
| `AWARD_SUBMITTED` | SponsoredAwardList | Sponsored_Award | the list of awards submitted to a sponsor. note that this field might not be used in a QSO record. It might be used to convey information about a user's "Award Account" between an award sponsor and the user. For example, AA6YQ might submit a request for awards by sending the following: <CALL:5>AA6YQ <AWARD_SUBMITTED:64>ADIF_CENTURY_BASIC,ADIF_CENTURY_SILVER,ADIF_SPECTRUM_100-160m |  |  |  |
| `AWARD_GRANTED` | SponsoredAwardList | Sponsored_Award | the list of awards granted by a sponsor. note that this field might not be used in a QSO record. It might be used to convey information about a user's "Award Account" between an award sponsor and the user. For example, in response to a request "send me a list of the awards granted to AA6YQ", this might be received: <CALL:5>AA6YQ <AWARD_GRANTED:64>ADIF_CENTURY_BASIC,ADIF_CENTURY_SILVER,ADIF_SPECTRUM_100-160m |  |  |  |
| `A_INDEX` | Number |  | the geomagnetic A index at the time of the QSO in the range 0 to 400 (inclusive) | 0 | 400 |  |
| `BAND` | Enumeration | Band | QSO Band |  |  |  |
| `BAND_RX` | Enumeration | Band | in a split frequency QSO, the logging station's receiving band |  |  |  |
| `CALL` | String |  | the contacted station's callsign |  |  |  |
| `CHECK` | String |  | contest check (e.g. for ARRL Sweepstakes) |  |  |  |
| `CLASS` | String |  | contest class (e.g. for ARRL Field Day) |  |  |  |
| `CLUBLOG_QSO_UPLOAD_DATE` | Date |  | the date the QSO was last uploaded to the Club Log online service |  |  |  |
| `CLUBLOG_QSO_UPLOAD_STATUS` | Enumeration | QSO_Upload_Status | the upload status of the QSO on the Club Log online service |  |  |  |
| `CNTY` | Enumeration | Secondary_Administrative_Subdivision[DXCC] | the contacted station's Secondary Administrative Subdivision (e.g. US county, JA Gun), in the specified format |  |  |  |
| `CNTY_ALT` | SecondaryAdministrativeSubdivisionListAlt |  | a semicolon (;) delimited, unordered list of Secondary Administrative Subdivision Alt codes for the contacted station See the Data Type for details. |  |  |  |
| `COMMENT` | String |  | comment field for QSO for a message to be incorporated in a paper or electronic QSL for the contacted station's operator, use the QSLMSG field recommended use: information of interest to the contacted station's operator |  |  |  |
| `COMMENT_INTL` | IntlString |  | comment field for QSO for a message to be incorporated in a paper or electronic QSL for the contacted station's operator, use the QSLMSG_INTL field recommended use: information of interest to the contacted station's operator |  |  |  |
| `CONT` | Enumeration | Continent | the contacted station's Continent |  |  |  |
| `CONTACTED_OP` | String |  | the callsign of the individual operating the contacted station |  |  |  |
| `CONTEST_ID` | String | Contest_ID | QSO Contest Identifier use enumeration values for interoperability |  |  |  |
| `COUNTRY` | String |  | the contacted station's DXCC entity name |  |  |  |
| `COUNTRY_INTL` | IntlString |  | the contacted station's DXCC entity name |  |  |  |
| `CQZ` | PositiveInteger |  | the contacted station's CQ Zone in the range 1 to 40 (inclusive) | 1 | 40 |  |
| `CREDIT_SUBMITTED` | CreditList,AwardList | Credit,Award | the list of credits sought for this QSO Use of data type AwardList and enumeration Award are import-only |  |  |  |
| `CREDIT_GRANTED` | CreditList,AwardList | Credit,Award | the list of credits granted to this QSO Use of data type AwardList and enumeration Award are import-only |  |  |  |
| `DARC_DOK` | Enumeration |  | the contacted station's DARC DOK (District Location Code) A DOK comprises letters and numbers, e.g. <DARC_DOK:3>A01 Note that DARC provides two different lists - one for DOKs and one for Special DOKs. |  |  |  |
| `DCL_QSLRDATE` | Date |  | date QSL received from DCL (only valid if DCL_QSL_RCVD is Y, I, or V)(V import-only) |  |  |  |
| `DCL_QSLSDATE` | Date |  | date QSL sent to DCL (only valid if DCL_QSL_SENT is Y, Q, or I) |  |  |  |
| `DCL_QSL_RCVD` | Enumeration | QSL_Rcvd | DCL QSL received status Default Value: N |  |  |  |
| `DCL_QSL_SENT` | Enumeration | QSL_Sent | DCL QSL sent status Default Value: N |  |  |  |
| `DISTANCE` | Number |  | the distance between the logging station and the contacted station in kilometers via the specified signal path with a value greater than or equal to 0 | 0 |  |  |
| `DXCC` | Enumeration | DXCC_Entity_Code | the contacted station's DXCC Entity Code <DXCC:1>0 means that the contacted station is known not to be within a DXCC entity. |  |  |  |
| `EMAIL` | String |  | the contacted station's email address |  |  |  |
| `EQ_CALL` | String |  | the contacted station's owner's callsign |  |  |  |
| `EQSL_AG` | Enumeration | EQSL_AG | indicates whether the QSO is known to be "Authenticity Guaranteed" by eQSL Default value: U |  |  |  |
| `EQSL_QSLRDATE` | Date |  | date QSL received from eQSL.cc (only valid if EQSL_QSL_RCVD is Y, I, or V)(V import-only) |  |  |  |
| `EQSL_QSLSDATE` | Date |  | date QSL sent to eQSL.cc (only valid if EQSL_QSL_SENT is Y, Q, or I) |  |  |  |
| `EQSL_QSL_RCVD` | Enumeration | QSL_Rcvd | eQSL.cc QSL received status instead of V (import-only) use <CREDIT_GRANTED:42>CQWAZ:eqsl,CQWAZ_BAND:eqsl,CQWAZ_MODE:eqsl Default Value: N |  |  |  |
| `EQSL_QSL_SENT` | Enumeration | QSL_Sent | eQSL.cc QSL sent status Default Value: N |  |  |  |
| `FISTS` | PositiveInteger |  | the contacted station's FISTS CW Club member number with a value greater than 0. | 1 |  |  |
| `FISTS_CC` | PositiveInteger |  | the contacted station's FISTS CW Club Century Certificate (CC) number with a value greater than 0. | 1 |  |  |
| `FORCE_INIT` | Boolean |  | new EME "initial" |  |  |  |
| `FREQ` | Number |  | QSO frequency in Megahertz |  |  |  |
| `FREQ_RX` | Number |  | in a split frequency QSO, the logging station's receiving frequency in Megahertz |  |  |  |
| `GRIDSQUARE` | GridSquare |  | the contacted station's 2-character, 4-character, 6-character, or 8-character Maidenhead Grid Square For 10 or 12 character locators, store the first 8 characters in GRIDSQUARE and the additional 2 or 4 characters in the GRIDSQUARE_EXT field |  |  |  |
| `GRIDSQUARE_EXT` | GridSquareExt |  | for a contacted station's 10-character Maidenhead locator, supplements the GRIDSQUARE field by containing characters 9 and 10. For a contacted station's 12-character Maidenhead locator, supplements the GRIDSQUARE field by containing characters 9, 10, 11 and 12. Characters 9 and 10 are case-insensitive ASCII letters in the range A-X. Characters 11 and 12 are Digits in the range 0 to 9. On export, the field length must be 2 or 4. On import, if the field length is greater than 4, the additional characters must be ignored. Example of exporting the 10-character locator FN01MH42BQ: <GRIDSQUARE:8>FN01MH42 <GRIDSQUARE_EXT:2>BQ |  |  |  |
| `GUEST_OP` | String |  | import-only: use OPERATOR instead |  |  | true |
| `HAMLOGEU_QSO_UPLOAD_DATE` | Date |  | the date the QSO was last uploaded to the HAMLOG.EU online service |  |  |  |
| `HAMLOGEU_QSO_UPLOAD_STATUS` | Enumeration | QSO_Upload_Status | the upload status of the QSO on the HAMLOG.EU online service |  |  |  |
| `HAMQTH_QSO_UPLOAD_DATE` | Date |  | the date the QSO was last uploaded to the HamQTH.com online service |  |  |  |
| `HAMQTH_QSO_UPLOAD_STATUS` | Enumeration | QSO_Upload_Status | the upload status of the QSO on the HamQTH.com online service |  |  |  |
| `HRDLOG_QSO_UPLOAD_DATE` | Date |  | the date the QSO was last uploaded to the HRDLog.net online service |  |  |  |
| `HRDLOG_QSO_UPLOAD_STATUS` | Enumeration | QSO_Upload_Status | the upload status of the QSO on the HRDLog.net online service |  |  |  |
| `IOTA` | IOTARefNo |  | the contacted station's IOTA designator, in format CC-XXX, where CC is a member of the Continent enumeration XXX is the island group designator, where 1 <= XXX <= 999 [use leading zeroes] |  |  |  |
| `IOTA_ISLAND_ID` | PositiveInteger |  | the contacted station's IOTA Island Identifier, an 8-digit integer in the range 1 to 99999999 [leading zeroes optional] | 1 | 99999999 |  |
| `ITUZ` | PositiveInteger |  | the contacted station's ITU zone in the range 1 to 90 (inclusive) | 1 | 90 |  |
| `K_INDEX` | Integer |  | the geomagnetic K index at the time of the QSO in the range 0 to 9 (inclusive) | 0 | 9 |  |
| `LAT` | Location |  | the contacted station's latitude |  |  |  |
| `LON` | Location |  | the contacted station's longitude |  |  |  |
| `LOTW_QSLRDATE` | Date |  | date QSL received from ARRL Logbook of the World (only valid if LOTW_QSL_RCVD is Y, I, or V)(V import-only) |  |  |  |
| `LOTW_QSLSDATE` | Date |  | date QSL sent to ARRL Logbook of the World (only valid if LOTW_QSL_SENT is Y, Q, or I) |  |  |  |
| `LOTW_QSL_RCVD` | Enumeration | QSL_Rcvd | ARRL Logbook of the World QSL received status instead of V (import-only) use <CREDIT_GRANTED:39>DXCC:lotw,DXCC_BAND:lotw,DXCC_MODE:lotw Default Value: N |  |  |  |
| `LOTW_QSL_SENT` | Enumeration | QSL_Sent | ARRL Logbook of the World QSL sent status Default Value: N |  |  |  |
| `MAX_BURSTS` | Number |  | maximum length of meteor scatter bursts heard by the logging station, in seconds with a value greater than or equal to 0 | 0 |  |  |
| `MODE` | Enumeration | Mode | QSO Mode |  |  |  |
| `MORSE_KEY_INFO` | String |  | details of the contacted station's Morse key (e.g. make, model, etc). Example: <MORSE_KEY_INFO:16>Begali Sculpture |  |  |  |
| `MORSE_KEY_TYPE` | Enumeration | Morse_Key_Type | the contacted station's Morse key type (e.g. straight key, bug, etc). Example for a dual-lever paddle: <MORSE_KEY_TYPE:2>DP |  |  |  |
| `MS_SHOWER` | String |  | For Meteor Scatter QSOs, the name of the meteor shower in progress |  |  |  |
| `MY_ALTITUDE` | Number |  | the height of the logging station in meters relative to Mean Sea Level (MSL). For example 1.5 km is <MY_ALTITUDE:4>1500 and 10.5 m is <MY_ALTITUDE:4>10.5 |  |  |  |
| `MY_ANTENNA` | String |  | the logging station's antenna |  |  |  |
| `MY_ANTENNA_INTL` | IntlString |  | the logging station's antenna |  |  |  |
| `MY_ARRL_SECT` | Enumeration | ARRL_Section | the logging station's ARRL section |  |  |  |
| `MY_CITY` | String |  | the logging station's city |  |  |  |
| `MY_CITY_INTL` | IntlString |  | the logging station's city |  |  |  |
| `MY_CNTY` | Enumeration | Secondary_Administrative_Subdivision[MY_DXCC] | the logging station's Secondary Administrative Subdivision (e.g. US county, JA Gun), in the specified format |  |  |  |
| `MY_CNTY_ALT` | SecondaryAdministrativeSubdivisionListAlt |  | a semicolon (;) delimited, unordered list of Secondary Administrative Subdivision Alt codes for the logging station See the Data Type for details. |  |  |  |
| `MY_COUNTRY` | String | Country | the logging station's DXCC entity name |  |  |  |
| `MY_COUNTRY_INTL` | IntlString | Country | the logging station's DXCC entity name |  |  |  |
| `MY_CQ_ZONE` | PositiveInteger |  | the logging station's CQ Zone in the range 1 to 40 (inclusive) | 1 | 40 |  |
| `MY_DARC_DOK` | Enumeration |  | the logging station's DARC DOK (District Location Code) A DOK comprises letters and numbers, e.g. <MY_DARC_DOK:3>A01 Note that DARC provides two different lists - one for DOKs and one for Special DOKs. |  |  |  |
| `MY_DXCC` | Enumeration | DXCC_Entity_Code | the logging station's DXCC Entity Code <MY_DXCC:1>0 means that the logging station is known not to be within a DXCC entity. |  |  |  |
| `MY_FISTS` | PositiveInteger |  | the logging station's FISTS CW Club member number with a value greater than 0. | 1 |  |  |
| `MY_GRIDSQUARE` | GridSquare |  | the logging station's 2-character, 4-character, 6-character, or 8-character Maidenhead Grid Square For 10 or 12 character locators, store the first 8 characters in MY_GRIDSQUARE and the additional 2 or 4 characters in the MY_GRIDSQUARE_EXT field |  |  |  |
| `MY_GRIDSQUARE_EXT` | GridSquareExt |  | for a logging station's 10-character Maidenhead locator, supplements the MY_GRIDSQUARE field by containing characters 9 and 10. For a logging station's 12-character Maidenhead locator, supplements the MY_GRIDSQUARE field by containing characters 9, 10, 11 and 12. Characters 9 and 10 are case-insensitive ASCII letters in the range A-X. Characters 11 and 12 are Digits in the range 0 to 9. On export, the field length must be 2 or 4. On import, if the field length is greater than 4, the additional characters must be ignored. Example of exporting the 10-character locator FN01MH42BQ: <MY_GRIDSQUARE:8>FN01MH42 <MY_GRIDSQUARE_EXT:2>BQ |  |  |  |
| `MY_IOTA` | IOTARefNo |  | the logging station's IOTA designator, in format CC-XXX, where CC is a member of the Continent enumeration XXX is the island group designator, where 1 <= XXX <= 999 [use leading zeroes] |  |  |  |
| `MY_IOTA_ISLAND_ID` | PositiveInteger |  | the logging station's IOTA Island Identifier, an 8-digit integer in the range 1 to 99999999 [leading zeroes optional] | 1 | 99999999 |  |
| `MY_ITU_ZONE` | PositiveInteger |  | the logging station's ITU zone in the range 1 to 90 (inclusive) | 1 | 90 |  |
| `MY_LAT` | Location |  | the logging station's latitude |  |  |  |
| `MY_LON` | Location |  | the logging station's longitude |  |  |  |
| `MY_MORSE_KEY_INFO` | String |  | details of the logging station's Morse key (e.g. make, model, etc). Example: <MY_MORSE_KEY_INFO:16>Begali Sculpture |  |  |  |
| `MY_MORSE_KEY_TYPE` | Enumeration | Morse_Key_Type | the logging station's Morse key type (e.g. straight key, bug, etc). Example for a dual-lever paddle: <MORSE_KEY_TYPE:2>DP |  |  |  |
| `MY_NAME` | String |  | the logging operator's name |  |  |  |
| `MY_NAME_INTL` | IntlString |  | the logging operator's name |  |  |  |
| `MY_POSTAL_CODE` | String |  | the logging station's postal code |  |  |  |
| `MY_POSTAL_CODE_INTL` | IntlString |  | the logging station's postal code |  |  |  |
| `MY_POTA_REF` | POTARefList |  | a comma-delimited list of one or more of the logging station's POTA (Parks on the Air) reference(s). Examples: <MY_POTA_REF:6>K-0059 <MY_POTA_REF:7>K-10000 <MY_POTA_REF:40>K-0817,K-4566,K-4576,K-4573,K-4578@US-WY |  |  |  |
| `MY_RIG` | String |  | description of the logging station's equipment |  |  |  |
| `MY_RIG_INTL` | IntlString |  | description of the logging station's equipment |  |  |  |
| `MY_SIG` | String |  | special interest activity or event |  |  |  |
| `MY_SIG_INTL` | IntlString |  | special interest activity or event |  |  |  |
| `MY_SIG_INFO` | String |  | special interest activity or event information |  |  |  |
| `MY_SIG_INFO_INTL` | IntlString |  | special interest activity or event information |  |  |  |
| `MY_SOTA_REF` | SOTARef |  | the logging station's International SOTA Reference. |  |  |  |
| `MY_STATE` | Enumeration | Primary_Administrative_Subdivision[MY_DXCC] | the code for the logging station's Primary Administrative Subdivision (e.g. US State, JA Island, VE Province) |  |  |  |
| `MY_STREET` | String |  | the logging station's street |  |  |  |
| `MY_STREET_INTL` | IntlString |  | the logging station's street |  |  |  |
| `MY_USACA_COUNTIES` | SecondarySubdivisionList |  | two US counties in the case where the logging station is located on a border between two counties, representing counties that the contacted station may claim for the CQ Magazine USA-CA award program. E.g. MA,Franklin:MA,Hampshire |  |  |  |
| `MY_VUCC_GRIDS` | GridSquareList |  | two or four adjacent Maidenhead grid locators, each four or six characters long, representing the logging station's grid squares that the contacted station may claim for the ARRL VUCC award program. E.g. EM98,FM08,EM97,FM07 |  |  |  |
| `MY_WWFF_REF` | WWFFRef |  | the logging station's WWFF (World Wildlife Flora & Fauna) reference |  |  |  |
| `NAME` | String |  | the contacted station's operator's name |  |  |  |
| `NAME_INTL` | IntlString |  | the contacted station's operator's name |  |  |  |
| `NOTES` | MultilineString |  | QSO notes recommended use: information of interest to the logging station's operator |  |  |  |
| `NOTES_INTL` | IntlMultilineString |  | QSO notes recommended use: information of interest to the logging station's operator |  |  |  |
| `NR_BURSTS` | Integer |  | the number of meteor scatter bursts heard by the logging station with a value greater than or equal to 0 | 0 |  |  |
| `NR_PINGS` | Integer |  | the number of meteor scatter pings heard by the logging station with a value greater than or equal to 0 | 0 |  |  |
| `OPERATOR` | String |  | the logging operator's callsign if STATION_CALLSIGN is absent, OPERATOR shall be treated as both the logging station's callsign and the logging operator's callsign |  |  |  |
| `OWNER_CALLSIGN` | String |  | the callsign of the owner of the station used to log the contact (the callsign of the OPERATOR's host) if OWNER_CALLSIGN is absent, STATION_CALLSIGN shall be treated as both the logging station's callsign and the callsign of the owner of the station |  |  |  |
| `PFX` | String |  | the contacted station's WPX prefix |  |  |  |
| `POTA_REF` | POTARefList |  | a comma-delimited list of one or more of the contacted station's POTA (Parks on the Air) reference(s). Examples: <POTA_REF:6>K-5033 <POTA_REF:13>VE-5082@CA-AB <POTA_REF:40>K-0817,K-4566,K-4576,K-4573,K-4578@US-WY |  |  |  |
| `PRECEDENCE` | String |  | contest precedence (e.g. for ARRL Sweepstakes) |  |  |  |
| `PROP_MODE` | Enumeration | Propagation_Mode | QSO propagation mode |  |  |  |
| `PUBLIC_KEY` | String |  | public encryption key |  |  |  |
| `QRZCOM_QSO_DOWNLOAD_DATE` | Date |  | date QSO downloaded from QRZ.COM logbook |  |  |  |
| `QRZCOM_QSO_DOWNLOAD_STATUS` | Enumeration | QSO_Download_Status | QRZ.COM logbook QSO download status |  |  |  |
| `QRZCOM_QSO_UPLOAD_DATE` | Date |  | the date the QSO was last uploaded to the QRZ.COM online service |  |  |  |
| `QRZCOM_QSO_UPLOAD_STATUS` | Enumeration | QSO_Upload_Status | the upload status of the QSO on the QRZ.COM online service |  |  |  |
| `QSLMSG` | MultilineString |  | a message for the contacted station's operator to be incorporated in a paper or electronic QSL |  |  |  |
| `QSLMSG_INTL` | IntlMultilineString |  | a message for the contacted station's operator to be incorporated in a paper or electronic QSL |  |  |  |
| `QSLMSG_RCVD` | MultilineString |  | a message addressed to the logging station's operator incorporated in a paper or electronic QSL |  |  |  |
| `QSLRDATE` | Date |  | QSL received date (only valid if QSL_RCVD is Y, I, or V)(V import-only) |  |  |  |
| `QSLSDATE` | Date |  | QSL sent date (only valid if QSL_SENT is Y, Q, or I) |  |  |  |
| `QSL_RCVD` | Enumeration | QSL_Rcvd | QSL received status instead of V (import-only) use <CREDIT_GRANTED:39>DXCC:card,DXCC_BAND:card,DXCC_MODE:card Default Value: N |  |  |  |
| `QSL_RCVD_VIA` | Enumeration | QSL_Via | if QSL_RCVD is set to 'Y' or 'V', the means by which the QSL was received by the logging station; otherwise, the means by which the logging station requested or intends to request that the QSL be conveyed. (Note: 'V' is import-only) use of M (manager) is import-only |  |  |  |
| `QSL_SENT` | Enumeration | QSL_Sent | QSL sent status Default Value: N |  |  |  |
| `QSL_SENT_VIA` | Enumeration | QSL_Via | if QSL_SENT is set to 'Y', the means by which the QSL was sent by the logging station; otherwise, the means by which the logging station intends to convey the QSL use of M (manager) is import-only |  |  |  |
| `QSL_VIA` | String |  | the contacted station's QSL route |  |  |  |
| `QSO_COMPLETE` | Enumeration | QSO_Complete | indicates whether the QSO was complete from the perspective of the logging station Y - yes N - no NIL - not heard ? - uncertain |  |  |  |
| `QSO_DATE` | Date |  | date on which the QSO started |  |  |  |
| `QSO_DATE_OFF` | Date |  | date on which the QSO ended |  |  |  |
| `QSO_RANDOM` | Boolean |  | indicates whether the QSO was random or scheduled |  |  |  |
| `QTH` | String |  | the contacted station's city |  |  |  |
| `QTH_INTL` | IntlString |  | the contacted station's city |  |  |  |
| `REGION` | Enumeration | Region | the contacted station's WAE or CQ entity contained within a DXCC entity. the value None indicates that the WAE or CQ entity is the DXCC entity in the DXCC field. nothing can be inferred from the absence of the REGION field |  |  |  |
| `RIG` | MultilineString |  | description of the contacted station's equipment |  |  |  |
| `RIG_INTL` | IntlMultilineString |  | description of the contacted station's equipment |  |  |  |
| `RST_RCVD` | String |  | signal report from the contacted station |  |  |  |
| `RST_SENT` | String |  | signal report sent to the contacted station |  |  |  |
| `RX_PWR` | Number |  | the contacted station's transmitter power in Watts with a value greater than or equal to 0 | 0 |  |  |
| `SAT_MODE` | String |  | satellite mode - a code representing the satellite's uplink band and downlink band |  |  |  |
| `SAT_NAME` | String |  | name of satellite |  |  |  |
| `SFI` | Integer |  | the solar flux at the time of the QSO in the range 0 to 300 (inclusive). | 0 | 300 |  |
| `SIG` | String |  | the name of the contacted station's special activity or interest group |  |  |  |
| `SIG_INTL` | IntlString |  | the name of the contacted station's special activity or interest group |  |  |  |
| `SIG_INFO` | String |  | information associated with the contacted station's activity or interest group |  |  |  |
| `SIG_INFO_INTL` | IntlString |  | information associated with the contacted station's activity or interest group |  |  |  |
| `SILENT_KEY` | Boolean |  | 'Y' indicates that the contacted station's operator is now a Silent Key. |  |  |  |
| `SKCC` | String |  | the contacted station's Straight Key Century Club (SKCC) member information |  |  |  |
| `SOTA_REF` | SOTARef |  | the contacted station's International SOTA Reference. |  |  |  |
| `SRX` | Integer |  | contest QSO received serial number with a value greater than or equal to 0 | 0 |  |  |
| `SRX_STRING` | String |  | contest QSO received information use Cabrillo format to convey contest information for which ADIF fields are not specified in the event of a conflict between information in a dedicated contest field and this field, information in the dedicated contest field shall prevail |  |  |  |
| `STATE` | Enumeration | Primary_Administrative_Subdivision[DXCC] | the code for the contacted station's Primary Administrative Subdivision (e.g. US State, JA Island, VE Province) |  |  |  |
| `STATION_CALLSIGN` | String |  | the logging station's callsign (the callsign used over the air) if STATION_CALLSIGN is absent, OPERATOR shall be treated as both the logging station's callsign and the logging operator's callsign |  |  |  |
| `STX` | Integer |  | contest QSO transmitted serial number with a value greater than or equal to 0 | 0 |  |  |
| `STX_STRING` | String |  | contest QSO transmitted information use Cabrillo format to convey contest information for which ADIF fields are not specified in the event of a conflict between information in a dedicated contest field and this field, information in the dedicated contest field shall prevail |  |  |  |
| `SUBMODE` | String | Submode[MODE] | QSO Submode use enumeration values for interoperability |  |  |  |
| `SWL` | Boolean |  | indicates that the QSO information pertains to an SWL report |  |  |  |
| `TEN_TEN` | PositiveInteger |  | Ten-Ten number with a value greater than 0 | 1 |  |  |
| `TIME_OFF` | Time |  | HHMM or HHMMSS in UTC in the absence of <QSO_DATE_OFF>, the QSO duration is less than 24 hours. For example, the following is a QSO starting at 14 July 2020 23:55 and finishing at 15 July 2020 01:00: <QSO_DATE:8>20200714 <TIME_ON:4>2355 <TIME_OFF:4>0100 |  |  |  |
| `TIME_ON` | Time |  | HHMM or HHMMSS in UTC |  |  |  |
| `TX_PWR` | Number |  | the logging station's power in Watts with a value greater than or equal to 0 | 0 |  |  |
| `UKSMG` | PositiveInteger |  | the contacted station's UKSMG member number with a value greater than 0 | 1 |  |  |
| `USACA_COUNTIES` | SecondarySubdivisionList |  | two US counties in the case where the contacted station is located on a border between two counties, representing counties credited to the QSO for the CQ Magazine USA-CA award program. E.g. MA,Franklin:MA,Hampshire |  |  |  |
| `VE_PROV` | String |  | import-only: use STATE instead |  |  | true |
| `VUCC_GRIDS` | GridSquareList |  | two or four adjacent Maidenhead grid locators, each four or six characters long, representing the contacted station's grid squares credited to the QSO for the ARRL VUCC award program. E.g. EM98,FM08,EM97,FM07 |  |  |  |
| `WEB` | String |  | the contacted station's URL |  |  |  |
| `WWFF_REF` | WWFFRef |  | the contacted station's WWFF (World Wildlife Flora & Fauna) reference |  |  |  |

### 1.3 Enumerations (25; 3,345 values)

| Enumeration | Values | Import-only values | Columns |
|---|---:|---:|---|
| `Ant_Path` | 4 | 0 | Abbreviation, Meaning, Import-only, Comments |
| `ARRL_Section` | 90 | 0 | Abbreviation, Section Name, DXCC Entity Code, From Date, Deleted Date, Import-only, Comments |
| `Award` | 29 | 29 | Award, Import-only, Comments |
| `Award_Sponsor` | 11 | 0 | Sponsor, Sponsoring Organization, Import-only, Comments |
| `Band` | 33 | 0 | Band, Lower Freq (MHz), Upper Freq (MHz), Import-only, Comments |
| `Contest_ID` | 256 | 4 | Contest-ID, Description, Import-only, Comments |
| `Continent` | 7 | 0 | Abbreviation, Continent, Import-only, Comments |
| `Credit` | 71 | 0 | Credit For, Sponsor, Award, Facet, Import-only, Comments |
| `DXCC_Entity_Code` | 403 | 0 | Entity Code, Entity Name, Deleted, Import-only, Comments |
| `EQSL_AG` | 3 | 0 | Status, Description, Import-only, Comments |
| `Mode` | 91 | 42 | Mode, Submodes, Description, Import-only, Comments |
| `Morse_Key_Type` | 7 | 0 | Abbreviation, Meaning, Characteristics, Morse Composition, Examples, Import-only, Comments |
| `Primary_Administrative_Subdivision` | 1965 | 50 | Code, Primary Administrative Subdivision, DXCC Entity Code, Contained Within, Oblast #, CQ Zone, ITU Zone, Prefix, Deleted, Import-only, Comments |
| `Propagation_Mode` | 20 | 0 | Enumeration, Description, Import-only, Comments |
| `QSL_Medium` | 3 | 0 | Medium, Description, Import-only, Comments |
| `QSL_Rcvd` | 5 | 1 | Status, Meaning, Description, Import-only, Comments |
| `QSL_Sent` | 5 | 0 | Status, Meaning, Description, Import-only, Comments |
| `QSL_Via` | 4 | 1 | Via, Description, Import-only, Comments |
| `QSO_Complete` | 4 | 0 | Abbreviation, Meaning, Import-only, Comments |
| `QSO_Download_Status` | 3 | 0 | Status, Description, Import-only, Comments |
| `QSO_Upload_Status` | 3 | 0 | Status, Description, Import-only, Comments |
| `Region` | 10 | 0 | Region Entity Code, DXCC Entity Code, Region, Prefix, Applicability, Start Date, End Date, Import-only, Comments |
| `Secondary_Administrative_Subdivision` | 58 | 0 | Code, Secondary Administrative Subdivision, DXCC Entity Code, Alaska Judicial District, Deleted, Import-only, Comments |
| `Secondary_Administrative_Subdivision_Alt` | 73 | 0 | Code, DXCC Entity Code, Region, District, Deleted, Import-only, Comments |
| `Submode` | 187 | 0 | Submode, Mode, Description, Import-only, Comments |

Every value of every enumeration is in PostgreSQL `adif.<enumeration>` (ionis-core#33), loaded from the same checksummed file.

## Part 2 — IONIS-AI extension

Defines, in ADIF's structure, only what ADIF does not. **Empty: no entry is added until it is reviewed.**
The work list is `spec/inventory.json`: every field in our tables today, 238 names, of which 182 have no ADIF definition.

