import 'package:flutter/material.dart';

class RouteStatusCard extends StatelessWidget {
  final int routesAssigned;
  final int routesCompleted;
  final int totalAwb;
  final int totalKoli;

  const RouteStatusCard({
    super.key,
    required this.routesAssigned,
    required this.routesCompleted,
    required this.totalAwb,
    required this.totalKoli,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildGridItem('Rute Ditugaskan', routesAssigned.toString())),
            const SizedBox(width: 12),
            Expanded(child: _buildGridItem('Rute Selesai', routesCompleted.toString())),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildGridItem('Total AWB', totalAwb.toString())),
            const SizedBox(width: 12),
            Expanded(child: _buildGridItem('Total KOLI', totalKoli.toString())),
          ],
        ),
      ],
    );
  }

  Widget _buildGridItem(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0D47A1),
            ),
          ),
        ],
      ),
    );
  }
}
