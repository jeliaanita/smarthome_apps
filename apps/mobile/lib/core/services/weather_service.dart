

import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class WeatherData {
  final String city;
  final String description;
  final String descriptionDetail;
  final double tempC;
  final double humidity;
  final String icon; 
  final DateTime date;

  const WeatherData({
    required this.city,
    required this.description,
    required this.descriptionDetail,
    required this.tempC,
    required this.humidity,
    required this.icon,
    required this.date,
  });

  String get formattedDate {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${days[date.weekday - 1]}, ${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }
}

class WeatherService {
  static final WeatherService instance = WeatherService._();
  WeatherService._();

  static const _apiKey = 'b9aab5a2d330edd1104d27ed96bf2d76';
  static const _baseUrl = 'https://api.openweathermap.org/data/2.5';

  WeatherData? _cached;
  DateTime? _lastFetch;

  WeatherData? get cached => _cached;

  Future<WeatherData?> getWeather() async {
    if (_cached != null && _lastFetch != null) {
      final diff = DateTime.now().difference(_lastFetch!);
      if (diff.inMinutes < 10) return _cached;
    }

    try {
      final position = await _getPosition();
      if (position == null) return null;

      final url = Uri.parse(
        '$_baseUrl/weather'
        '?lat=${position.latitude}'
        '&lon=${position.longitude}'
        '&appid=$_apiKey'
        '&units=metric'
        '&lang=en',
      );

      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final weather = json['weather'][0] as Map<String, dynamic>;
      final main    = json['main']    as Map<String, dynamic>;

      _cached = WeatherData(
        city:              json['name'] ?? '',
        description:       _capitalize(weather['main'] ?? ''),
        descriptionDetail: _capitalize(weather['description'] ?? ''),
        tempC:             (main['temp'] as num).toDouble(),
        humidity:          (main['humidity'] as num).toDouble(),
        icon:              weather['icon'] ?? '01d',
        date:              DateTime.now(),
      );
      _lastFetch = DateTime.now();
      return _cached;
    } catch (e) {
      return null;
    }
  }

  Future<Position?> _getPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low, 
        timeLimit: Duration(seconds: 10),
      ),
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}