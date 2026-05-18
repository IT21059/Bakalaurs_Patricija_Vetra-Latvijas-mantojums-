import 'package:flutter/material.dart'; //flutter bibliotēka
import 'package:google_maps_flutter/google_maps_flutter.dart'; 
import 'package:url_launcher/url_launcher.dart';
import '../sparql_service.dart'; //sparql datu ieguvei no fuseki
import 'package:geolocator/geolocator.dart'; //lokācijai
import 'add_object_page.dart'; //jauna objekta pievienošanas lapa
import 'weather_service.dart'; //laika prognozei

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

String _getPropertyCode(String field) {
  switch (field) {
    case 'title':
      return 'P102_has_title'; //objekta nosaukums
    case 'creator':
      return 'E21_Person'; //izveidotājs
    case 'constructionYear': //kad radīts
      return 'E12_Production';
    case 'related':
      return 'P67_refers_to'; //saistošie objekti
    case 'object':
      return 'E22_Human-Made_Object'; //objekts
    default:
      return '';
  }
}

// 🔹 formatē label + kodu
String _labelWithCode(String label, String field) {
  final code = _getPropertyCode(field);
  return code.isNotEmpty ? '$label ($code)' : label;
}

class _MapPageState extends State<MapPage> {
  static const LatLng _pValmiera = LatLng(57.5410, 25.4270);

  GoogleMapController? controller;
  final SparqlService sparqlService = SparqlService();
  final TextEditingController searchController = TextEditingController();
  final WeatherService weatherService = WeatherService();

  Set<Marker> markers = {};
  List<Map<String, dynamic>> objects = [];
  List<Map<String, dynamic>> filteredObjects = [];
  Map<String, dynamic>? selectedObject;
  List<Map<String, String>> relatedObjects = [];

  LatLng? currentLocation;

  bool radiusEnabled = false;
  double radiusMeters = 3000;

  bool _showInfo = false;
  bool _loading = true;

  double? currentTemperature;
  int? currentWeatherCode;
  bool? isDay;

  @override
  void initState() {
    super.initState();
    _loadObjectsFromFuseki();
    _getCurrentLocation();
    searchController.addListener(_filterObjects);
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

//_normalize funckija tika labota ar MI palīdzību
  String _normalize(String text) { //normalizē tekstu meklēšanai
    return text
        .toLowerCase()
        .replaceAll('ā', 'a')
        .replaceAll('č', 'c')
        .replaceAll('ē', 'e')
        .replaceAll('ģ', 'g')
        .replaceAll('ī', 'i')
        .replaceAll('ķ', 'k')
        .replaceAll('ļ', 'l')
        .replaceAll('ņ', 'n')
        .replaceAll('š', 's')
        .replaceAll('ū', 'u')
        .replaceAll('ž', 'z');
  }

  List<Map<String, dynamic>> _deduplicate(List<Map<String, dynamic>> data) {
    final seen = <String>{};
    return data.where((obj) {
      final key = obj['uri'].toString();
      return seen.add(key);
    }).toList();
  }

  Future<void> _loadWeather() async { //ielādē laika prognozi atkarībā no lietotāja lokācijas
    if (currentLocation == null) return;

    final weather = await weatherService.fetchCurrentWeather(
      currentLocation!.latitude,
      currentLocation!.longitude,
    );

    if (weather == null || !mounted) return;

    setState(() {
      currentTemperature = (weather['temperature'] as num?)?.toDouble();
      currentWeatherCode = weather['weatherCode'] as int?;
      isDay = (weather['isDay'] ?? 1) == 1;
    });
  }

//weatherIcon funkcija tika labota ar MI palīdzību
  IconData _weatherIcon(int? code, bool isDayTime) {
    if (code == null) return Icons.cloud;

    switch (code) {
      case 0:
        return isDayTime ? Icons.wb_sunny : Icons.nightlight_round;
      case 1:
      case 2:
        return isDayTime ? Icons.wb_cloudy : Icons.nights_stay;
      case 3:
        return Icons.cloud;
      case 45:
      case 48:
        return Icons.foggy;
      case 51:
      case 53:
      case 55:
      case 56:
      case 57:
      case 61:
      case 63:
      case 65:
      case 66:
      case 67:
      case 80:
      case 81:
      case 82:
        return Icons.grain;
      case 71:
      case 73:
      case 75:
      case 77:
      case 85:
      case 86:
        return Icons.ac_unit;
      case 95:
      case 96:
      case 99:
        return Icons.thunderstorm;
      default:
        return Icons.cloud;
    }
  }

  Widget _buildWeatherChip() {
    if (currentTemperature == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _weatherIcon(currentWeatherCode, isDay ?? true),
            size: 20,
          ),
          const SizedBox(width: 4),
          Text('${currentTemperature!.round()}°C'),
        ],
      ),
    );
  }

//_getCurrentLocation funkcija tika labota ar MI palīdzību
  Future<bool> _getCurrentLocation() async { //dabū lietotāja lokāciju
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return false;
      }

      if (permission == LocationPermission.deniedForever) return false;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 5),
      );

      if (!mounted) return false;

      setState(() {
        currentLocation = LatLng(position.latitude, position.longitude);
      });

      await _loadWeather();

      debugPrint('NEW LOCATION: ${position.latitude}, ${position.longitude}');
      return true;
    } catch (e) {
      debugPrint('Location error: $e');
      return false;
    }
  }
//rādiusa filtrēšanas funkcija
  List<Map<String, dynamic>> _filterByRadius(List<Map<String, dynamic>> data) {
    if (!radiusEnabled || currentLocation == null) return data;

    return data.where((obj) {
      final d = Geolocator.distanceBetween(
        currentLocation!.latitude,
        currentLocation!.longitude,
        obj['lat'],
        obj['lon'],
      );
      return d <= radiusMeters;
    }).toList();
  }
//objektu meklēšanas filtrs
  List<Map<String, dynamic>> _applyFilter(List<Map<String, dynamic>> data) {
    final q = _normalize(searchController.text.trim());
    if (q.isEmpty) return data;

    return data.where((o) {
      final t = _normalize((o['title'] ?? '').toString());
      return t.contains(q);
    }).toList();
  }

  Future<void> _loadObjectsFromFuseki() async { //tiek ielādēti objekti no fuseki un izveidojas marķieri
    try {
      final data = _deduplicate(await sparqlService.fetchObjects());
      final filtered = _deduplicate(_applyFilter(_filterByRadius(data)));

      final newMarkers = filtered.map((obj) {
        return Marker(
          markerId: MarkerId(obj['uri']),
          position: LatLng(obj['lat'], obj['lon']),
          onTap: () async {
            if (_showInfo && selectedObject?['uri'] == obj['uri']) {
              setState(() {
                _showInfo = false;
                selectedObject = null;
                relatedObjects = [];
              });
              return;
            }
//ielādē saistošos objektus
            final related = await sparqlService.fetchRelatedObjects(obj['uri']);

            if (!mounted) return;

            setState(() {
              selectedObject = obj;
              relatedObjects = related;
              _showInfo = true;
            });
          },
        );
      }).toSet();

      if (!mounted) return;

      setState(() {
        objects = data;
        filteredObjects = filtered;
        markers = newMarkers;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Fuseki load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _filterObjects() {
    final res = _deduplicate(_applyFilter(_filterByRadius(objects)));
    setState(() => filteredObjects = res);
    _loadObjectsFromFuseki();
  }

  Future<void> _goToMyLocation() async {
    if (currentLocation == null) {
      final ok = await _getCurrentLocation();
      if (!ok) return;
    }

    if (currentLocation == null || controller == null) return;

    await controller!.animateCamera(
      CameraUpdate.newLatLngZoom(currentLocation!, 16),
    );
  }

  Future<void> _toggleRadius() async { //iesl;edz vai izslēdz rādiusu
    if (currentLocation == null) {
      final ok = await _getCurrentLocation();
      if (!ok) return;
    }

    if (currentLocation == null) return;

    setState(() {
      radiusEnabled = !radiusEnabled;
    });

    _loadObjectsFromFuseki();
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openAddObjectPage() { //atveras lapa jauna objekta pievienošanai
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AddObjectPage(),
      ),
    );
  }

  Future<void> _openCreatorInfo(String creatorUri) async { //atveras izveidotāja informāciju
    if (creatorUri.trim().isEmpty) return;

    final creator = await sparqlService.fetchCreatorDetails(creatorUri);
    if (!mounted || creator == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _buildCreatorInfoSheet(creator),
    );
  }

  Widget _buildCreatorInfoSheet(Map<String, dynamic> creator) {
    final related = (creator['relatedObjects'] as List<dynamic>? ?? [])
        .map((e) => Map<String, String>.from(e as Map))
        .toList();

    final birthValue = ((creator['birthDate'] ?? '').toString().trim().isNotEmpty
            ? creator['birthDate']
            : creator['birthYear'] ?? '')
        .toString()
        .trim();

    final deathValue = ((creator['deathDate'] ?? '').toString().trim().isNotEmpty
            ? creator['deathDate']
            : creator['deathYear'] ?? '')
        .toString()
        .trim();

    final imageUrl = (creator['image'] ?? '').toString().trim();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.25,
      maxChildSize: 0.9,
      builder: (_, ctrl) {
        return Material(
          elevation: 12,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: ListView(
            controller: ctrl,
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Aizvērt',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text( //izveidotāja vārds
                (creator['label'] ?? 'Bez nosaukuma')
                    .toString()
                    .replaceAll('_', ' '),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (imageUrl.isNotEmpty) ...[ //attēls
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(
                      maxHeight: 260,
                    ),
                    color: Colors.grey.shade100,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 180,
                          color: Colors.grey.shade300,
                          alignment: Alignment.center,
                          child: const Text('Attēlu neizdevās ielādēt'),
                        );
                      },
                    ),
                  ),
                ),
              ],
              if ((creator['biographicalNote'] ?? '') //apraksts
                  .toString()
                  .trim()
                  .isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Apraksts',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text((creator['biographicalNote'] ?? '').toString()),
              ],
              if (birthValue.isNotEmpty || deathValue.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Dzīves laiks',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6), //dzīves laiks
                Text(
                  '${birthValue.isEmpty ? '?' : birthValue} – ${deathValue.isEmpty ? '' : deathValue}',
                ),
              ], //nodarbošanās
              if ((creator['occupation'] ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Nodarbošanās',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text((creator['occupation'] ?? '').toString()),
              ],
              if (related.isNotEmpty) ...[ //saistošie objekti
                const SizedBox(height: 16),
                const Text(
                  'Saistītie objekti',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                ...related.map(
                  (relatedObj) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: InkWell(
                      onTap: () async {
                        Navigator.of(context).pop();
                        await _focusOnRelatedObject(relatedObj);
                      },
                      child: Text(
                        '• ${(relatedObj['title'] ?? '').replaceAll('_', ' ')}',
                        style: const TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _focusOnObject(Map<String, dynamic> obj) async {
    final related = await sparqlService.fetchRelatedObjects(obj['uri'].toString());

    if (!mounted) return;

    setState(() {
      selectedObject = obj;
      relatedObjects = related;
      _showInfo = true;
    });

    if (controller != null) {
      await controller!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(obj['lat'] as double, obj['lon'] as double),
          16,
        ),
      );
    }
  }

//_focusOnRelatedObject funkcija tika labota ar MI palīdzību
  Future<void> _focusOnRelatedObject(Map<String, String> related) async {
    final relatedUri = related['uri'];
    if (relatedUri == null || relatedUri.isEmpty) return;

    Map<String, dynamic>? foundObject;

    for (final obj in objects) {
      if ((obj['uri'] ?? '').toString() == relatedUri) {
        foundObject = obj;
        break;
      }
    }

    if (foundObject == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Neizdevās atrast saistīto objektu kartē'),
        ),
      );
      return;
    }

    await _focusOnObject(foundObject);
  }

  Widget _buildSearchBox() {
    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Column(
        children: [
          Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(14),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: 'Meklēt objektu...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchController.text.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          searchController.clear();
                          _filterObjects();
                        },
                        icon: const Icon(Icons.clear),
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (searchController.text.trim().isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 8,
                    color: Colors.black12,
                  ),
                ],
              ),
              child: filteredObjects.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Nekas netika atrasts'),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: filteredObjects.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final obj = filteredObjects[index];
                        return ListTile(
                          title: Text((obj['title'] ?? '').toString()),
                          onTap: () async {
                            searchController.clear();
                            _filterObjects();
                            await _focusOnObject(obj);
                          },
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buttons() {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Positioned(
      right: 16,
      bottom: bottomInset + 90,
      child: Column(
        children: [
          FloatingActionButton(
            heroTag: 'zoom_in',
            mini: true,
            onPressed: () => controller?.animateCamera(CameraUpdate.zoomIn()),
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'zoom_out',
            mini: true,
            onPressed: () => controller?.animateCamera(CameraUpdate.zoomOut()),
            child: const Icon(Icons.remove),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'add_object',
            onPressed: _openAddObjectPage,
            child: const Icon(Icons.add_location_alt),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'radius',
            onPressed: _toggleRadius,
            child: Icon(
              radiusEnabled ? Icons.radar : Icons.radar_outlined,
            ),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'my_location',
            onPressed: _goToMyLocation,
            child: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }

  Widget _buildRadiusSlider() {
    if (!radiusEnabled || currentLocation == null) {
      return const SizedBox.shrink();
    }

    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Positioned(
      left: 16,
      right: 90,
      bottom: bottomInset + 24,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Rādiuss: ${(radiusMeters / 1000).toStringAsFixed(1)} km',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Slider(
                min: 500,
                max: 80000,
                divisions: 159,
                value: radiusMeters,
                label: '${(radiusMeters / 1000).toStringAsFixed(1)} km',
                onChanged: (value) {
                  setState(() {
                    radiusMeters = value;
                  });
                },
                onChangeEnd: (value) {
                  _loadObjectsFromFuseki();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

//_info() funkcija tika labota ar MI palīdzību
  Widget _info() {
    if (!_showInfo || selectedObject == null) return const SizedBox();

    final obj = selectedObject!;
    final images = (obj['images'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();

    final links = (obj['links'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();

    return Align(
      alignment: Alignment.bottomCenter,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.4,
        minChildSize: 0.2,
        maxChildSize: 0.9,
        builder: (_, ctrl) {
          return Material(
            elevation: 12,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
            child: ListView(
              controller: ctrl,
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 42,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Aizvērt',
                      onPressed: () {
                        setState(() {
                          _showInfo = false;
                          selectedObject = null;
                          relatedObjects = [];
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
Text(
  '${_labelWithCode((obj['title'] ?? '').toString(), 'title')}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if ((obj['snippet'] ?? '').toString().isNotEmpty)
                  Text(
                    (obj['snippet'] ?? '').toString(),
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                if ((obj['mainText'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text((obj['mainText'] ?? '').toString()),
                ],
                if (images.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Attēli',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 150,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: images.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final image = images[index];
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            image,
                            width: 200,
                            height: 150,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 200,
                                height: 150,
                                color: Colors.grey.shade300,
                                alignment: Alignment.center,
                                child: const Text('Attēlu neizdevās ielādēt'),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (links.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Saites',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...links.map(
                    (link) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: InkWell(
                        onTap: () => _openLink(link),
                        child: Text(
                          link,
                          style: const TextStyle(
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                if ((obj['constructionYear'] ?? '').toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
RichText(
  text: TextSpan(
    style: const TextStyle(
      fontSize: 14,
      color: Colors.black,
    ),
    children: [
      TextSpan(
        text: '${_labelWithCode('Celšanas laiks', 'constructionYear')}: ',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      TextSpan(
        text: (obj['constructionYear'] ?? '').toString(),
      ),
    ],
  ),
),
                ],
                if ((obj['creatorLabel'] ?? '').toString().trim().isNotEmpty) ...[
  const SizedBox(height: 6),
  Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${_labelWithCode('Izveidotājs', 'creator')}: ',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      Expanded(
        child: GestureDetector(
          onTap: () async {
            await _openCreatorInfo(
              (obj['creatorUri'] ?? '').toString(),
            );
          },
          child: Text(
            (obj['creatorLabel'] ?? '')
                .toString()
                .replaceAll('_', ' '),
            style: const TextStyle(
              color: Colors.blue,
              decoration: TextDecoration.underline,
              fontSize: 14,
            ),
          ),
        ),
      ),
    ],
  ),
],
                if (relatedObjects.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Objekti tuvumā',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...relatedObjects.map(
                    (related) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: InkWell(
                        onTap: () async {
                          await _focusOnRelatedObject(related);
                        },
                        child: Text(
                          '• ${(related['title'] ?? '').replaceAll('_', ' ')}',
                          style: const TextStyle(
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allMarkers = {
      ...markers,
      if (currentLocation != null)
        Marker(
          markerId: const MarkerId('me'),
          position: currentLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueBlue,
          ),
        ),
    };

    final circles = {
      if (radiusEnabled && currentLocation != null)
        Circle(
          circleId: const CircleId('r'),
          center: currentLocation!,
          radius: radiusMeters,
          fillColor: Colors.blue.withOpacity(0.2),
          strokeColor: Colors.blue,
        ),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Latvijas mantojums'),
        actions: [
          _buildWeatherChip(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _loadObjectsFromFuseki();
              await _getCurrentLocation();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            GoogleMap(
              onMapCreated: (c) => controller = c,
              initialCameraPosition: const CameraPosition(
                target: _pValmiera,
                zoom: 13,
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom,
              ),
              markers: allMarkers,
              circles: circles,
              myLocationEnabled: currentLocation != null,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              onTap: (_) => setState(() {
                _showInfo = false;
                selectedObject = null;
                relatedObjects = [];
              }),
            ),
            _buildSearchBox(),
            if (!_showInfo) _buildRadiusSlider(),
            _info(),
            if (!_showInfo) _buttons(),
            if (_loading) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}