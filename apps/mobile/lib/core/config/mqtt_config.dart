import 'package:shared_preferences/shared_preferences.dart';

/// Penyimpanan konfigurasi broker MQTT, mengikuti pola yang sama persis
/// dengan OpenHABConfig supaya konsisten dengan konfigurasi server openHAB.
// ignore: avoid_classes_with_only_static_members
class MqttConfig {
  static const _keyBroker    = 'mqtt_broker_host';
  static const _keyPort      = 'mqtt_broker_port';
  static const _keyWsPort    = 'mqtt_broker_ws_port';
  static const _keyUsername  = 'mqtt_username';
  static const _keyPassword  = 'mqtt_password';
  static const _keyUseTls    = 'mqtt_use_tls';
  static const _keyTopicData = 'mqtt_topic_data';
  static const _keyTopicLwt  = 'mqtt_topic_lwt';

  // Default mengikuti konfigurasi lama, supaya upgrade dari versi
  // sebelumnya tidak mendadak kehilangan data sebelum user setting ulang.
  static const defaultBroker    = 'broker.emqx.io';
  static const defaultPort      = 1883;
  static const defaultWsPort    = 8083;
  static const defaultTopicData = 'powermeter/pop/mbloc/jkt/data';
  static const defaultTopicLwt  = 'powermeter/pop/mbloc/jkt/LWT';

  static Future<String> getBroker() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBroker) ?? defaultBroker;
  }

  static Future<int> getPort() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyPort) ?? defaultPort;
  }

  static Future<int> getWsPort() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyWsPort) ?? defaultWsPort;
  }

  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUsername);
  }

  static Future<String?> getPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPassword);
  }

  static Future<bool> getUseTls() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyUseTls) ?? false;
  }

  static Future<String> getTopicData() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyTopicData) ?? defaultTopicData;
  }

  static Future<String> getTopicLwt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyTopicLwt) ?? defaultTopicLwt;
  }

  static Future<void> setBroker(String host) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBroker, host.trim());
  }

  static Future<void> setPort(int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPort, port);
  }

  static Future<void> setWsPort(int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyWsPort, port);
  }

  static Future<void> setUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, username);
  }

  static Future<void> setPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPassword, password);
  }

  static Future<void> setUseTls(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseTls, value);
  }

  static Future<void> setTopicData(String topic) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTopicData, topic.trim());
  }

  static Future<void> setTopicLwt(String topic) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTopicLwt, topic.trim());
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyBroker);
    await prefs.remove(_keyPort);
    await prefs.remove(_keyWsPort);
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyPassword);
    await prefs.remove(_keyUseTls);
    await prefs.remove(_keyTopicData);
    await prefs.remove(_keyTopicLwt);
  }

  static bool isValidPort(int port) => port > 0 && port <= 65535;
}