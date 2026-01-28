import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class GiphyService {
  final String _apiKey = 'SwXgiDsqVDzasGGOhQkgTbqytajt07ov';
  final String _baseUrl = 'https://api.giphy.com/v1/gifs/';

  Future<List<String>> fetchTrending({int offset = 0}) async {
    final url = Uri.parse(
      '${_baseUrl}trending?api_key=$_apiKey&limit=20&offset=$offset&rating=g',
    );
    return _parseResponse(url);
  }

  Future<List<String>> search(String query, {int offset = 0}) async {
    final url = Uri.parse(
      '${_baseUrl}search?api_key=$_apiKey&q=$query&limit=20&offset=$offset&rating=g',
    );
    return _parseResponse(url);
  }

  Future<List<String>> _parseResponse(Uri url) async {
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List<dynamic> results = data['data'];
        // iphy structures: images -> fixed_height -> url

        return results
            .map<String>(
              (gif) => gif['images']['fixed_height']['url'] as String,
            )
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint("Error fetching Giphy: $e");
      return [];
    }
  }
}
