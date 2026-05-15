import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherService {
  Future<Map<String, dynamic>?> fetchCurrentWeather(
    double latitude,
    double longitude,
  ) async {
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$latitude'
      '&longitude=$longitude'
      '&current=temperature_2m,weather_code,is_day',
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      return null;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final current = data['current'] as Map<String, dynamic>?;

    if (current == null) return null;

    return {
      'temperature': current['temperature_2m'],
      'weatherCode': current['weather_code'],
      'isDay': current['is_day'],
    };
  }
}