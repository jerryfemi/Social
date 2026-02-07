import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social/providers/chat_stats_provider.dart';

class ChatStatsCircular extends ConsumerWidget {
  final String groupId;

  const ChatStatsCircular({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(chatStatsProvider(groupId));
    final total = stats['total'] as int;
    final counts = stats['counts'] as Map<String, int>;

    if (total == 0) return const SizedBox.shrink();

    // Prepare sections
    // Limit to top 5 contributors, group rest as "Others"
    final sortedEntries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topEntries = sortedEntries.take(5).toList();
    final otherEntries = sortedEntries.skip(5).toList();

    int othersCount = 0;
    for (var e in otherEntries) {
      othersCount += e.value;
    }

    final List<MapEntry<String, int>> chartData = [...topEntries];
    if (othersCount > 0) {
      chartData.add(MapEntry('Others', othersCount));
    }

    // Colors pallette
    final colors = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.grey, // for Others
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Column(
        children: [
          const Text(
            'Stats',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          // PIE CHART
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: List.generate(chartData.length, (index) {
                  final entry = chartData[index];
                  final isOthers = entry.key == 'Others';
                  final color = isOthers
                      ? Colors.grey
                      : colors[index % colors.length];

                  return PieChartSectionData(
                    color: color,
                    value: entry.value.toDouble(),
                    title: '${entry.value}', // Show Count on slice
                    radius: 50,
                    titleStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // LEGEND
          Column(
            children: List.generate(chartData.length, (index) {
              final entry = chartData[index];
              final userId = entry.key;
              final count = entry.value;
              final color = userId == 'Others'
                  ? Colors.grey
                  : colors[index % colors.length];

              if (userId == 'Others') {
                return _buildLegendItem('Others', count, color);
              }

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('Users')
                    .doc(userId)
                    .get(),
                builder: (context, snapshot) {
                  String name = 'Loading...';
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final data = snapshot.data!.data() as Map<String, dynamic>;
                    name = data['username'] ?? 'User';
                  }
                  return _buildLegendItem(name, count, color);
                },
              );
            }),
          ),
          const SizedBox(height: 10),
          Text(
            '$total Messages Total',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String name, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            '$name: $count',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
