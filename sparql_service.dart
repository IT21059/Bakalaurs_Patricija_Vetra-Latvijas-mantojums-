import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

//sparql izpildīšana un realizēšana ar select vaicājumiem no apache jena fuseki datu bāzes
class SparqlService {
  static const String endpoint = 'https://fuseki.hillhouse.tech/History/sparql';

  Map<String, String> _headers() {
    return {
      'Accept': 'application/sparql-results+json',
    };
  }

  Future<http.Response> _runSelect(String query) async {
    //izpilda sparql select vaicājumu ar get pieprasījumu
    final uri = Uri.parse(endpoint).replace(
      queryParameters: {
        'query': query,
      },
    );

    final response = await http
        .get(uri, headers: _headers())
        .timeout(const Duration(seconds: 20));

    //debug gadījumā ja ir kļūdas no fuseki debugPrint
    debugPrint('SPARQL URI: $uri');
    debugPrint('SPARQL STATUS: ${response.statusCode}');
    debugPrint('SPARQL BODY: ${response.body}');

    return response;
  }

  Future<List<Map<String, dynamic>>> fetchObjects() async { //pie query labošanas un pareizas palaišanas tika izmantota MI palīdzība
    const query = r'''
PREFIX crm: <http://www.cidoc-crm.org/cidoc-crm/>
PREFIX geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

SELECT ?obj ?titleLabel ?address ?lat ?lon ?snippetVal ?mainTextVal ?linksVal ?imageVal ?creator ?creatorLabel ?constructionYearVal
WHERE {
  ?obj a crm:E22_Human-Made_Object ;
       crm:P102_has_title ?title ;
       crm:P55_has_current_location ?place .

  OPTIONAL { ?title rdfs:label ?titleLabel . }

  OPTIONAL {
    ?place crm:P3_has_note ?addressRaw .
    BIND(STR(?addressRaw) AS ?address)
  }

  OPTIONAL {
    ?place geo:lat ?latRaw .
    BIND(STR(?latRaw) AS ?lat)
  }

  OPTIONAL {
    ?place geo:lon ?lonRaw .
    BIND(STR(?lonRaw) AS ?lon)
  }

  OPTIONAL {
    ?obj ?pSnippet ?snippetRaw .
    ?pSnippet rdfs:label ?pSnippetLabel .
    FILTER(CONTAINS(LCASE(STR(?pSnippetLabel)), "snippet"))
    BIND(STR(?snippetRaw) AS ?snippetVal)
  }

  OPTIONAL {
    ?obj ?pMain ?mainTextRaw .
    ?pMain rdfs:label ?pMainLabel .
    FILTER(CONTAINS(LCASE(STR(?pMainLabel)), "main"))
    BIND(STR(?mainTextRaw) AS ?mainTextVal)
  }

  OPTIONAL {
    ?obj ?pLinks ?linksRaw .
    ?pLinks rdfs:label ?pLinksLabel .
    FILTER(CONTAINS(LCASE(STR(?pLinksLabel)), "link"))
    BIND(STR(?linksRaw) AS ?linksVal)
  }

  OPTIONAL {
    ?obj ?pImage ?imageRaw .
    ?pImage rdfs:label ?pImageLabel .
    FILTER(CONTAINS(LCASE(STR(?pImageLabel)), "image"))
    BIND(STR(?imageRaw) AS ?imageVal)
  }

  OPTIONAL {
    ?obj crm:P108i_was_produced_by ?production .
    ?production crm:P14_carried_out_by ?creator .

    OPTIONAL { ?creator rdfs:label ?rdfsCreatorLabel . }

    OPTIONAL {
      ?creator ?p ?creatorLabelRaw .
      ?p rdfs:label ?pLabel .
      FILTER(LCASE(STR(?pLabel)) = "label")
    }

    BIND(COALESCE(?rdfsCreatorLabel, ?creatorLabelRaw) AS ?creatorLabel)
  }

  OPTIONAL {
    ?obj ?pYear ?constructionYearRaw .
    ?pYear rdfs:label ?pYearLabel .
    FILTER(LCASE(STR(?pYearLabel)) = "constructionyear")
    BIND(STR(?constructionYearRaw) AS ?constructionYearVal)
  }
}
ORDER BY ?titleLabel
''';

    final response = await _runSelect(query);

    if (response.statusCode != 200) {
      throw Exception('Fuseki error: ${response.statusCode}\n${response.body}');
    }

    final jsonData = jsonDecode(response.body) as Map<String, dynamic>;

    //parsē sparql json rezultātus
    final results = jsonData['results']['bindings'] as List<dynamic>;

    final Map<String, Map<String, dynamic>> grouped = {};

    for (final item in results) {
      final row = item as Map<String, dynamic>;

      final uri = (row['obj']?['value'] ?? '').toString();
      if (uri.isEmpty) continue;

      final latRaw =
          //koordinātas ar punktu, ne komatu
          (row['lat']?['value'] ?? '').toString().replaceAll(',', '.');

      final lonRaw =
          (row['lon']?['value'] ?? '').toString().replaceAll(',', '.');

      grouped.putIfAbsent(uri, () {
        //izveido objektu
        return <String, dynamic>{
          'uri': uri,
          'title': (row['titleLabel']?['value'] ?? 'Bez nosaukuma').toString(),
          'address': (row['address']?['value'] ?? '').toString(),
          'lat': double.tryParse(latRaw) ?? 0.0,
          'lon': double.tryParse(lonRaw) ?? 0.0,
          'snippet': (row['snippetVal']?['value'] ?? '').toString(),
          'mainText': (row['mainTextVal']?['value'] ?? '').toString(),
          'historyText': '',
          'links': <String>[],
          'images': <String>[],
          'creatorUri': (row['creator']?['value'] ?? '').toString(),
          'creatorLabel': (row['creatorLabel']?['value'] ?? '').toString(),
          'constructionYear': (row['constructionYearVal']?['value'] ?? '').toString(),
        };
      });

      final obj = grouped[uri]!;

      final link = (row['linksVal']?['value'] ?? '').toString();
      //pievieno linkus
      if (link.isNotEmpty && !(obj['links'] as List<String>).contains(link)) {
        (obj['links'] as List<String>).add(link);
      }

      final image = (row['imageVal']?['value'] ?? '').toString();
      //pievieno attēlus
      if (image.isNotEmpty && !(obj['images'] as List<String>).contains(image)) {
        (obj['images'] as List<String>).add(image);
      }

      final snippet = (row['snippetVal']?['value'] ?? '').toString();
      //pievieno snippet
      if ((obj['snippet'] as String).isEmpty && snippet.isNotEmpty) {
        obj['snippet'] = snippet;
      }

      final mainText = (row['mainTextVal']?['value'] ?? '').toString();
      //pievieno galveno tekstu
      if ((obj['mainText'] as String).isEmpty && mainText.isNotEmpty) {
        obj['mainText'] = mainText;
      }

      final creatorUri = (row['creator']?['value'] ?? '').toString();
      final creatorLabel = (row['creatorLabel']?['value'] ?? '').toString();

      if ((obj['creatorUri'] as String).isEmpty && creatorUri.isNotEmpty) {
        obj['creatorUri'] = creatorUri;
      }

      if ((obj['creatorLabel'] as String).isEmpty && creatorLabel.isNotEmpty) {
        obj['creatorLabel'] = creatorLabel;
      }

      final constructionYear =
          //kad radīts objekts
          (row['constructionYearVal']?['value'] ?? '').toString();

      if ((obj['constructionYear'] as String).isEmpty && constructionYear.isNotEmpty) {
        obj['constructionYear'] = constructionYear;
      }
    }

    final parsed = grouped.values.where((obj) {
      return obj['uri'].toString().isNotEmpty &&
          obj['lat'] != 0.0 &&
          obj['lon'] != 0.0;
    }).toList();

    debugPrint('PARSED OBJECTS COUNT: ${parsed.length}');
    return parsed;
  }

  Future<List<Map<String, String>>> fetchRelatedObjects(String uri) async { //pie query pareizības un izpildes tika izmantota MI palīdzība
    const query = r'''
PREFIX crm: <http://www.cidoc-crm.org/cidoc-crm/>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

SELECT DISTINCT ?related ?relatedLabel
WHERE {
  <URI_PLACEHOLDER> a crm:E22_Human-Made_Object ;
                    crm:P67_refers_to ?related .

  OPTIONAL {
    ?related crm:P102_has_title ?title .
    ?title rdfs:label ?titleLabel .
  }

  OPTIONAL {
    ?related rdfs:label ?relLabel .
  }

  OPTIONAL {
    ?related crm:P2_has_type ?type .
    ?type rdfs:label ?typeLabel .
  }

  BIND(COALESCE(?titleLabel, ?relLabel, ?typeLabel) AS ?relatedLabel)
}
ORDER BY ?relatedLabel
''';

    final finalQuery = query.replaceFirst('URI_PLACEHOLDER', uri);

    final response = await _runSelect(finalQuery);

    if (response.statusCode != 200) {
      return [];
    }

    final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
    final results = jsonData['results']['bindings'] as List<dynamic>;

    return results.map((e) {
      final row = e as Map<String, dynamic>;
      return <String, String>{
        'uri': (row['related']?['value'] ?? '').toString(),
        'title': (row['relatedLabel']?['value'] ?? '').toString(),
      };
    }).where((item) {
      return item['uri']!.isNotEmpty && item['title']!.isNotEmpty;
    }).toList();
  }

  Future<Map<String, dynamic>?> fetchCreatorDetails(String uri) async { //pie pareizas query izpildes tika izmantota MI palīdzība
    const query = r'''
PREFIX crm: <http://www.cidoc-crm.org/cidoc-crm/>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

SELECT ?creator ?labelVal ?biographicalNoteVal ?birthDateVal ?birthYearVal ?deathDateVal ?deathYearVal ?occupationVal ?imageVal ?relatedObj ?relatedObjLabel ?relatedObj2 ?relatedObjLabel2
WHERE {
  BIND(<URI_PLACEHOLDER> AS ?creator)

  OPTIONAL { ?creator rdfs:label ?rdfsLabel . }

  OPTIONAL {
    ?creator ?pLabel ?labelRaw .
    ?pLabel rdfs:label ?pLabelName .
    FILTER(LCASE(STR(?pLabelName)) = "label")
  }

  BIND(COALESCE(?rdfsLabel, ?labelRaw) AS ?labelVal)

  OPTIONAL {
    ?creator ?pBio ?bioRaw .
    ?pBio rdfs:label ?pBioLabel .
    FILTER(LCASE(STR(?pBioLabel)) = "biographicalnote")
    BIND(STR(?bioRaw) AS ?biographicalNoteVal)
  }

  OPTIONAL {
    ?creator ?pBirthDate ?birthDateRaw .
    ?pBirthDate rdfs:label ?pBirthDateLabel .
    FILTER(LCASE(STR(?pBirthDateLabel)) = "birthdate")
    BIND(STR(?birthDateRaw) AS ?birthDateVal)
  }

  OPTIONAL {
    ?creator ?pBirthYear ?birthYearRaw .
    ?pBirthYear rdfs:label ?pBirthYearLabel .
    FILTER(LCASE(STR(?pBirthYearLabel)) = "birthyear")
    BIND(STR(?birthYearRaw) AS ?birthYearVal)
  }

  OPTIONAL {
    ?creator ?pDeathDate ?deathDateRaw .
    ?pDeathDate rdfs:label ?pDeathDateLabel .
    FILTER(LCASE(STR(?pDeathDateLabel)) = "deathdate")
    BIND(STR(?deathDateRaw) AS ?deathDateVal)
  }

  OPTIONAL {
    ?creator ?pDeathYear ?deathYearRaw .
    ?pDeathYear rdfs:label ?pDeathYearLabel .
    FILTER(LCASE(STR(?pDeathYearLabel)) = "deathyear")
    BIND(STR(?deathYearRaw) AS ?deathYearVal)
  }

  OPTIONAL {
    ?creator ?pOccupation ?occupationRaw .
    ?pOccupation rdfs:label ?pOccupationLabel .
    FILTER(LCASE(STR(?pOccupationLabel)) = "occupation")
    BIND(STR(?occupationRaw) AS ?occupationVal)
  }

  OPTIONAL {
    ?creator ?pImage ?imageRaw .
    ?pImage rdfs:label ?pImageLabel .
    FILTER(CONTAINS(LCASE(STR(?pImageLabel)), "image"))
    BIND(STR(?imageRaw) AS ?imageVal)
  }

  OPTIONAL {
    ?creator ?pAssoc ?relatedObj .
    ?pAssoc rdfs:label ?pAssocLabel .
    FILTER(LCASE(STR(?pAssocLabel)) = "associatedwithobject")

    OPTIONAL {
      ?relatedObj crm:P102_has_title ?relatedTitle .
      ?relatedTitle rdfs:label ?relatedTitleLabel .
    }

    OPTIONAL {
      ?relatedObj rdfs:label ?relatedRdfsLabel .
    }

    BIND(COALESCE(?relatedTitleLabel, ?relatedRdfsLabel) AS ?relatedObjLabel)
  }

  OPTIONAL {
    ?production crm:P14_carried_out_by ?creator .
    ?relatedObj2 crm:P108i_was_produced_by ?production .

    OPTIONAL {
      ?relatedObj2 crm:P102_has_title ?relatedTitle2 .
      ?relatedTitle2 rdfs:label ?relatedTitleLabel2 .
    }

    OPTIONAL {
      ?relatedObj2 rdfs:label ?relatedRdfsLabel2 .
    }

    BIND(COALESCE(?relatedTitleLabel2, ?relatedRdfsLabel2) AS ?relatedObjLabel2)
  }
}
ORDER BY ?relatedObjLabel ?relatedObjLabel2
''';

    final finalQuery = query.replaceFirst('URI_PLACEHOLDER', uri);

    final response = await _runSelect(finalQuery);

    if (response.statusCode != 200) {
      debugPrint('Creator query error: ${response.statusCode} ${response.body}');
      return null;
    }

    final jsonData = jsonDecode(response.body) as Map<String, dynamic>;

    final results = jsonData['results']['bindings'] as List<dynamic>;

    if (results.isEmpty) return null;

    final creator = <String, dynamic>{
      'uri': uri,
      'label': '',
      'biographicalNote': '',
      'birthDate': '',
      'deathDate': '',
      'birthYear': '',
      'deathYear': '',
      'occupation': '',
      'image': '',
      'relatedObjects': <Map<String, String>>[],
    };

    final seenRelated = <String>{};

    for (final item in results) {
      final row = item as Map<String, dynamic>;

      final label = (row['labelVal']?['value'] ?? '').toString();
      final bio = (row['biographicalNoteVal']?['value'] ?? '').toString();

      final birthDate =
          //dzimšanas/radīšanas gads
          (row['birthDateVal']?['value'] ?? '').toString().trim();

      final birthYear = (row['birthYearVal']?['value'] ?? '').toString().trim();

      final deathDate =
          //nāves/beigšanas gads
          (row['deathDateVal']?['value'] ?? '').toString().trim();

      final deathYear = (row['deathYearVal']?['value'] ?? '').toString().trim();

      final occupation = (row['occupationVal']?['value'] ?? '').toString();

      final image = (row['imageVal']?['value'] ?? '').toString();

      if ((creator['label'] as String).isEmpty && label.isNotEmpty) {
        creator['label'] = label;
      }

      if ((creator['biographicalNote'] as String).isEmpty && bio.isNotEmpty) {
        creator['biographicalNote'] = bio;
      }

      if ((creator['birthDate'] as String).isEmpty) {
        if (birthDate.isNotEmpty) {
          creator['birthDate'] = birthDate;
        } else if (birthYear.isNotEmpty) {
          creator['birthDate'] = birthYear;
        }
      }

      if ((creator['deathDate'] as String).isEmpty) {
        if (deathDate.isNotEmpty) {
          creator['deathDate'] = deathDate;
        } else if (deathYear.isNotEmpty) {
          creator['deathDate'] = deathYear;
        }
      }

      if ((creator['birthYear'] as String).isEmpty && birthYear.isNotEmpty) {
        creator['birthYear'] = birthYear;
      }

      if ((creator['deathYear'] as String).isEmpty && deathYear.isNotEmpty) {
        creator['deathYear'] = deathYear;
      }

      if ((creator['occupation'] as String).isEmpty && occupation.isNotEmpty) {
        creator['occupation'] = occupation;
      }

      if ((creator['image'] as String).isEmpty && image.isNotEmpty) {
        creator['image'] = image;
      }

      final relatedUri1 = (row['relatedObj']?['value'] ?? '').toString();
      final relatedLabel1 = (row['relatedObjLabel']?['value'] ?? '').toString();

      if (relatedUri1.isNotEmpty &&
          relatedLabel1.isNotEmpty &&
          seenRelated.add(relatedUri1)) {
        (creator['relatedObjects'] as List<Map<String, String>>).add({
          'uri': relatedUri1,
          'title': relatedLabel1,
        });
      }

      final relatedUri2 = (row['relatedObj2']?['value'] ?? '').toString();
      final relatedLabel2 = (row['relatedObjLabel2']?['value'] ?? '').toString();

      if (relatedUri2.isNotEmpty &&
          relatedLabel2.isNotEmpty &&
          seenRelated.add(relatedUri2)) {
        (creator['relatedObjects'] as List<Map<String, String>>).add({
          'uri': relatedUri2,
          'title': relatedLabel2,
        });
      }
    }

    return creator;
  }
}