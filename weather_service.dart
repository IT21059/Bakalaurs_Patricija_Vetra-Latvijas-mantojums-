import 'dart:convert';
import 'package:http/http.dart' as http;
// funkcija, kur parāda pašreizējo laika prognozi atkarībā no lietotāja atrašanās vietas, kur parādās prognozes emoji ikona un grādi. Šī funkcija gūta no Open-Meteo Api.
class WeatherService {
  //šī funkcija tika labota ar MI palīdzību
  Future<Map<String, dynamic>?> fetchCurrentWeather(
    double latitude,
    double longitude,
  ) async {
    final uri = Uri.parse( //izveidots api url ar parametriem
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$latitude'
      '&longitude=$longitude'
      '&current=temperature_2m,weather_code,is_day',
    );

//šeit MI palīdzēja dabūt http get pieprasījumu
    final response = await http.get(uri); //veikts get pieprasījums uz open-meteo api

    if (response.statusCode != 200) {
      return null;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>; //pārtaisa json par map
    final current = data['current'] as Map<String, dynamic>?;

    if (current == null) return null;

//MI palīdzēja izveidot strukturēšanu
    return {
      'temperature': current['temperature_2m'],
      'weatherCode': current['weather_code'],
      'isDay': current['is_day'],
    };
  }
}