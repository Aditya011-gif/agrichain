import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_app_bar.dart';
import '../../services/database_service.dart';
import '../../services/smart_contract_pdf_service.dart';
import '../../utils/crop_image_helper.dart';
import '../../utils/translation_helper.dart';
import '../../widgets/language_switcher.dart';
import '../../widgets/crop_tracking_map_sheet.dart';

class FarmerOrdersScreen extends StatefulWidget {
  const FarmerOrdersScreen({super.key});

  @override
  State<FarmerOrdersScreen> createState() => _FarmerOrdersScreenState();
}

class _FarmerOrdersScreenState extends State<FarmerOrdersScreen>
    with SingleTickerProviderStateMixin {
  final DatabaseService _dbService = DatabaseService();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final user = appState.currentUser;
    final farmerId = user?.id ?? '';
    final farmerName = user?.name.isNotEmpty == true ? user!.name : 'Kisan';

    return Scaffold(
      backgroundColor: AppTheme.backgroundGreen,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          CustomAppBar(
            title: context.tr('My Orders & Demands', 'मेरे ऑर्डर और मांगें'),
            subtitle: context.tr('Buyer Orders & Escrow Settlements', 'खरीदार ऑर्डर और एस्क्रो भुगतान'),
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 8),
                child: Center(child: LanguageSwitcherPill(isDark: true)),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppTheme.softShadow,
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: const Color(0xFF1B5E20),
                  unselectedLabelColor: AppTheme.textSecondary,
                  indicatorColor: const Color(0xFF1B5E20),
                  indicatorWeight: 3,
                  labelStyle: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  tabs: [
                    Tab(
                      icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                      text: context.tr('Retail Orders', 'खुदरा ऑर्डर'),
                    ),
                    Tab(
                      icon: const Icon(Icons.hub_outlined, size: 18),
                      text: context.tr('Buyer Demands', 'खरीदार मांगें'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildRetailOrdersTab(farmerId),
            _buildFarmerBulkDemandsTab(farmerId, farmerName),
          ],
        ),
      ),
    );
  }

  // Farmer -> Retail Buyer Orders
  Widget _buildRetailOrdersTab(String farmerId) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _dbService.streamFarmerRetailOrders(farmerId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final retailOrders = snapshot.data ?? [];

        if (retailOrders.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_bag_outlined, size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.35)),
                  const SizedBox(height: 14),
                  Text(
                    context.tr('No Retail Orders Yet', 'अभी तक कोई खुदरा ऑर्डर नहीं'),
                    style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr(
                      'When retail buyers order your crops on the AgriChain marketplace, their orders with locked escrow will appear here in real time for fulfillment.',
                      'जब खुदरा खरीदार आपकी फसलों का ऑर्डर देंगे, तो उनके एस्क्रो-सुरक्षित ऑर्डर यहां रीयल-टाइम में दिखाई देंगे।',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
          itemCount: retailOrders.length,
          itemBuilder: (context, index) {
            final order = retailOrders[index];
            final cropName = order['cropName'] ?? 'Farm Produce';
            final variety = order['variety'] ?? 'Standard';
            final grade = order['grade'] ?? 'Grade A';
            final imageUrl = order['imageUrl']?.toString() ?? '';
            final buyerName = order['buyerName'] ?? 'Retail Buyer';
            final buyerPhone = order['buyerPhone'] ?? 'Contact via App';
            final deliveryAddress = order['deliveryAddress'] ?? 'Standard Delivery';
            final qty = _toDouble(order['quantity']);
            final price = _toDouble(order['price'] ?? order['pricePerUnit']);
            final total = order['totalPrice'] != null ? _toDouble(order['totalPrice']) : (qty * price);
            final status = (order['status'] ?? 'active').toString().toLowerCase();
            final escrowStatus = (order['escrowStatus'] ?? 'LOCKED').toString();
            final orderId = (order['orderId'] ?? order['id'] ?? 'ORD-$index').toString();
            final dateStr = order['createdAt'] != null ? order['createdAt'].toString().split('T').first : 'Recent';
            final txHash = order['txHash']?.toString() ?? '0x7c4e...89a1';

            final isDelivered = status == 'delivered' || status == 'completed';
            final isInTransit = status == 'in_transit';

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Order Header Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      border: const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.receipt_long, size: 16, color: Color(0xFF2E7D32)),
                            const SizedBox(width: 6),
                            Text(
                              '${context.tr('Order', 'ऑर्डर')} #$orderId • $dateStr',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDelivered
                                ? const Color(0xFFDCFCE7)
                                : isInTransit
                                    ? const Color(0xFFEFF6FF)
                                    : const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isDelivered
                                ? context.tr('DELIVERED & SETTLED', 'वितरित व भुगतान संपन्न')
                                : isInTransit
                                    ? context.tr('IN TRANSIT', 'मार्ग में')
                                    : context.tr('SELECT DELIVERY', 'डिलीवरी चुनें'),
                            style: TextStyle(
                              color: isDelivered
                                  ? const Color(0xFF15803D)
                                  : isInTransit
                                      ? const Color(0xFF1D4ED8)
                                      : const Color(0xFFB45309),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 2. Crop Details & Financial Breakdown
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CropImageHelper.buildCropImage(
                                imageUrl,
                                cropName,
                                height: 72,
                                width: 72,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    cropName,
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          variety,
                                          style: const TextStyle(fontSize: 10, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE0F2FE),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          grade,
                                          style: const TextStyle(fontSize: 10, color: Color(0xFF0369A1), fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '$qty kg @ ₹$price/kg',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                                      ),
                                      Text(
                                        '₹${total.toStringAsFixed(0)}',
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 18,
                                          color: const Color(0xFF2E7D32),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // 3. Buyer & Delivery Info Tile
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.person, size: 14, color: Color(0xFF2563EB)),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${context.tr('Buyer', 'खरीदार')}: $buyerName',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                  ),
                                  const Spacer(),
                                  const Icon(Icons.phone, size: 12, color: Color(0xFF64748B)),
                                  const SizedBox(width: 4),
                                  Text(
                                    buyerPhone,
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.location_on, size: 14, color: Color(0xFFE11D48)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      deliveryAddress,
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Pre-Harvest Order Indicator
                        if (order['isPreHarvest'] == true) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAF5FF),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFD8B4FE)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.grass, size: 16, color: Color(0xFF7E22CE)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    context.tr(
                                      'Pre-Booked Standing Harvest • Est. Harvest in ${order['daysToHarvest'] ?? 15} days',
                                      'अग्रिम बुक की गई खड़ी फसल • अनुमानित कटाई ${order['daysToHarvest'] ?? 15} दिनों में',
                                    ),
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF6B21A8)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 10),

                        // 4. Polygon Smart Escrow Assurance Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDelivered
                                ? const Color(0xFFF0FDF4)
                                : const Color(0xFFFAF5FF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDelivered ? const Color(0xFFBBF7D0) : const Color(0xFFE9D5FF),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isDelivered ? Icons.verified_user : Icons.lock_outline,
                                size: 16,
                                color: isDelivered ? const Color(0xFF166534) : const Color(0xFF7E22CE),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  isDelivered
                                      ? context.tr(
                                          'Polygon Escrow: ₹${total.toStringAsFixed(0)} Settled to Bank ($escrowStatus)',
                                          'पॉलीगॉन एस्क्रो: ₹${total.toStringAsFixed(0)} बैंक में जमा ($escrowStatus)',
                                        )
                                      : context.tr(
                                          'Polygon Escrow: ₹${total.toStringAsFixed(0)} Locked (Tx: ${txHash.length > 12 ? "${txHash.substring(0, 10)}..." : txHash})',
                                          'पॉलीगॉन एस्क्रो: ₹${total.toStringAsFixed(0)} सुरक्षित लॉक (Tx: ${txHash.length > 12 ? "${txHash.substring(0, 10)}..." : txHash})',
                                        ),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDelivered ? const Color(0xFF166534) : const Color(0xFF7E22CE),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // 5. Dual-Signed Smart Contract PDF Action Button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              SmartContractPdfService.autoDownloadOrPreviewContract(
                                context: context,
                                order: order,
                              );
                            },
                            icon: const Icon(Icons.picture_as_pdf, color: Color(0xFF1B5E20), size: 18),
                            label: Text(
                              context.tr('📄 View Signed Smart Contract (PDF)', '📄 हस्ताक्षरित स्मार्ट अनुबंध देखें (PDF)'),
                              style: const TextStyle(
                                color: Color(0xFF1B5E20),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              side: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              backgroundColor: const Color(0xFFF0FDF4),
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Dual Tracking: Live Delivery Map
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => CropTrackingMapSheet.show(context, order, isFarmer: true),
                            icon: const Icon(Icons.map_outlined, color: Color(0xFF1D4ED8), size: 18),
                            label: Text(
                              context.tr('🗺️ Track Live Route & Delivery Map', '🗺️ लाइव रूट और डिलीवरी मैप ट्रैक करें'),
                              style: const TextStyle(
                                color: Color(0xFF1D4ED8),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              side: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              backgroundColor: const Color(0xFFEFF6FF),
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // 6. Farmer Actions: Dispatch & OTP Escrow Release
                        if (!isDelivered) ...[
                          if (!isInTransit) ...[
                            // Dispatch selection prompt
                            Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFFDE68A)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.pending_actions, color: Color(0xFFD97706), size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          context.tr('Fulfillment Pending: Select Delivery to Ship', 'डिलीवरी चयन लंबित: भेजने के लिए विकल्प चुनें'),
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF92400E)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    context.tr(
                                      'Buyer escrow payment is locked. Select whether you will Self-Deliver or request Delhivery pickup to ship this order.',
                                      'खरीदार का भुगतान एस्क्रो में सुरक्षित है। माल भेजने के लिए स्वयं डिलीवरी या दिल्लीवरी पिकअप का चयन करें।',
                                    ),
                                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF78350F), height: 1.3),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => _showFarmerDeliveryDispatchModal(context, order),
                                icon: const Icon(Icons.local_shipping, size: 18, color: Colors.white),
                                label: Text(
                                  context.tr('🚚 Choose Delivery & Ship Produce', '🚚 डिलीवरी विकल्प चुनें और माल भेजें'),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1D4ED8),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 2,
                                ),
                              ),
                            ),
                          ] else ...[
                            // In Transit details
                            Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFBFDBFE)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    order['deliveryOption'] == 'self' ? Icons.agriculture : Icons.local_shipping,
                                    color: const Color(0xFF1D4ED8),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          order['deliveryOption'] == 'self'
                                              ? context.tr('Dispatched via Farmer Self-Delivery', 'किसान स्वयं डिलीवरी द्वारा प्रेषित')
                                              : context.tr('Dispatched via ${order['logisticsProvider'] ?? 'Delhivery B2B Reefer'}', '${order['logisticsProvider'] ?? 'Delhivery B2B'} द्वारा प्रेषित'),
                                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                                        ),
                                        Text(
                                          order['deliveryOption'] == 'self'
                                              ? (order['selfDeliveryNotes']?.toString().isNotEmpty == true ? order['selfDeliveryNotes'].toString() : 'Direct transport arranged by seller')
                                              : 'Tracking: ${order['trackingNumber'] ?? 'DLHV-HR-8391'} • Slot: ${order['pickupSlot'] ?? 'Pickup Scheduled'}',
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF3B82F6)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => _showFarmerOtpClaimDialog(context, order),
                                icon: const Icon(Icons.pin, size: 16, color: Colors.white),
                                label: Text(
                                  context.tr('Claim Escrow (Enter Buyer OTP)', 'एस्क्रो भुगतान प्राप्त करें (OTP दर्ज करें)'),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2E7D32),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ] else ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle, color: Color(0xFF15803D), size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  context.tr('Delivery Handshake Complete • Escrow Payout Credited', 'डिलीवरी हैंडशेक पूर्ण • एस्क्रो भुगतान बैंक में जमा'),
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Delivery & Dispatch Method Modal for Farmer
  void _showFarmerDeliveryDispatchModal(BuildContext context, Map<String, dynamic> order) {
    final orderId = (order['orderId'] ?? order['id'] ?? '').toString();
    final buyerName = order['buyerName'] ?? 'Retail Buyer';
    final deliveryAddress = order['deliveryAddress'] ?? 'Standard Address';
    final cropName = order['cropName'] ?? 'Farm Crop';
    final qty = _toDouble(order['quantity']);

    String selectedMethod = 'platform';
    String selectedCarrier = 'Delhivery B2B Reefer';
    String selectedSlot = 'Tomorrow Morning (9:00 AM - 1:00 PM)';
    final notesController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              top: 20,
              left: 20,
              right: 20,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.local_shipping, color: Color(0xFF1D4ED8), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('Select Delivery & Ship Order', 'डिलीवरी विकल्प चुनें और माल भेजें'),
                              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                            ),
                            Text(
                              'Order #$orderId • $cropName (${qty.toStringAsFixed(0)} kg)',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Destination Info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on, size: 16, color: Color(0xFFE11D48)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${context.tr('Deliver to', 'वितरण पता')}: $buyerName',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                              ),
                              Text(
                                deliveryAddress,
                                style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    context.tr('Who will fulfill this delivery?', 'इस ऑर्डर की डिलीवरी कौन करेगा?'),
                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 10),

                  // Option A: Platform Logistics (Delhivery)
                  GestureDetector(
                    onTap: () => setModalState(() => selectedMethod = 'platform'),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: selectedMethod == 'platform' ? const Color(0xFFF0F9FF) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selectedMethod == 'platform' ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
                          width: selectedMethod == 'platform' ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                selectedMethod == 'platform' ? Icons.radio_button_checked : Icons.radio_button_off,
                                color: selectedMethod == 'platform' ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.local_shipping, size: 18, color: Color(0xFF0284C7)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  context.tr('Request AgriChain Platform Pickup (Delhivery)', 'एग्रीचेन प्लेटफॉर्म पिकअप (Delhivery)'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: selectedMethod == 'platform' ? const Color(0xFF0369A1) : const Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Doorstep Pickup',
                                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            context.tr(
                              'Certified carrier picks up directly from your farm gate with GPS telematics, tamper digital seal & transit insurance.',
                              'प्रमाणित डिलीवरी पार्टनर आपके खेत से सीधा उठाएगा, जीपीएस ट्रैकिंग और माल बीमा शामिल।',
                            ),
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.3),
                          ),
                          if (selectedMethod == 'platform') ...[
                            const SizedBox(height: 12),
                            const Divider(height: 1),
                            const SizedBox(height: 10),

                            // Carrier selector
                            Text(
                              context.tr('Select Carrier Partner:', 'लॉजिस्टिक्स पार्टनर चुनें:'),
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              children: [
                                'Delhivery B2B Reefer',
                                'WheelsEye Agri-Logistics',
                                'Rivigo Express',
                              ].map((c) {
                                final isC = selectedCarrier == c;
                                return ChoiceChip(
                                  label: Text(c, style: TextStyle(fontSize: 11, fontWeight: isC ? FontWeight.bold : FontWeight.normal)),
                                  selected: isC,
                                  selectedColor: const Color(0xFF0284C7),
                                  labelStyle: TextStyle(color: isC ? Colors.white : const Color(0xFF0F172A)),
                                  onSelected: (val) {
                                    if (val) setModalState(() => selectedCarrier = c);
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 10),

                            // Pickup slot selector
                            Text(
                              context.tr('Farm-Gate Pickup Slot:', 'खेत से पिकअप समय:'),
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              initialValue: selectedSlot,
                              decoration: InputDecoration(
                                isDense: true,
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'Today (4:00 PM - 7:00 PM)', child: Text('Today Evening (4 PM - 7 PM)', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: 'Tomorrow Morning (9:00 AM - 1:00 PM)', child: Text('Tomorrow Morning (9 AM - 1 PM)', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: 'Tomorrow Afternoon (2:00 PM - 6:00 PM)', child: Text('Tomorrow Afternoon (2 PM - 6 PM)', style: TextStyle(fontSize: 12))),
                              ],
                              onChanged: (v) {
                                if (v != null) setModalState(() => selectedSlot = v);
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Option B: Farmer Self-Delivery
                  GestureDetector(
                    onTap: () => setModalState(() => selectedMethod = 'self'),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: selectedMethod == 'self' ? const Color(0xFFFFFBEB) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selectedMethod == 'self' ? const Color(0xFFD97706) : const Color(0xFFCBD5E1),
                          width: selectedMethod == 'self' ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                selectedMethod == 'self' ? Icons.radio_button_checked : Icons.radio_button_off,
                                color: selectedMethod == 'self' ? const Color(0xFFD97706) : const Color(0xFF94A3B8),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.agriculture, size: 18, color: Color(0xFFB45309)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  context.tr('Farmer Self-Delivery (स्वयं पहुंचाएंगे)', 'किसान स्वयं डिलीवरी'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: selectedMethod == 'self' ? const Color(0xFFB45309) : const Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '0% Freight Fee',
                                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            context.tr(
                              'You deliver the produce directly using your own transport (tractor/vehicle) or arrange on-farm buyer pickup. Zero shipping fee deducted.',
                              'आप खुद अपने वाहन/ट्रैक्टर से माल खरीदार के पते पर पहुंचाएंगे या खेत से पिकअप कराएंगे। कोई शुल्क नहीं कटेगा।',
                            ),
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.3),
                          ),
                          if (selectedMethod == 'self') ...[
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: notesController,
                              decoration: InputDecoration(
                                labelText: context.tr('Driver / Vehicle Notes for Buyer', 'चालक / वाहन विवरण'),
                                hintText: 'e.g. Dispatched via tractor trolley HR-05-4321 by 4 PM',
                                hintStyle: const TextStyle(fontSize: 11),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.all(10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Confirm button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final isPlatform = selectedMethod == 'platform';
                        final trackingId = isPlatform
                            ? 'DLHV-HR-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}'
                            : 'SELF-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';

                        await _dbService.updateRetailOrderStatus(
                          orderId,
                          'in_transit',
                          extra: {
                            'deliveryOption': selectedMethod,
                            'logisticsProvider': isPlatform ? selectedCarrier : 'Farmer Self-Delivery',
                            'trackingNumber': trackingId,
                            'pickupSlot': isPlatform ? selectedSlot : null,
                            'selfDeliveryNotes': !isPlatform && notesController.text.trim().isNotEmpty
                                ? notesController.text.trim()
                                : null,
                            'deliveryConfirmedByFarmer': true,
                            'deliveryConfirmedAt': DateTime.now().toIso8601String(),
                          },
                        );

                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                isPlatform
                                    ? '🚚 Delhivery farm-gate pickup scheduled ($trackingId)! Order marked In Transit.'
                                    : '🚜 Farmer Self-Delivery confirmed! Order marked In Transit.',
                              ),
                              backgroundColor: const Color(0xFF15803D),
                              duration: const Duration(seconds: 4),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: selectedMethod == 'platform' ? const Color(0xFF0284C7) : const Color(0xFFD97706),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        selectedMethod == 'platform'
                            ? context.tr('Confirm Delhivery Pickup & Mark In Transit', 'दिल्लीवरी पिकअप पक्का करें व भेजें')
                            : context.tr('Confirm Self-Delivery & Mark In Transit', 'स्वयं डिलीवरी पक्की करें व भेजें'),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // OTP Claim Dialog for Doorstep Handshake
  void _showFarmerOtpClaimDialog(BuildContext context, Map<String, dynamic> order) {
    final otpController = TextEditingController();
    final expectedOtp = order['deliveryOtp']?.toString() ?? '';
    final orderId = (order['orderId'] ?? order['id'] ?? '').toString();
    final qty = _toDouble(order['quantity']);
    final price = _toDouble(order['price'] ?? order['pricePerUnit']);
    final total = order['totalPrice'] != null ? _toDouble(order['totalPrice']) : (qty * price);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.pin, color: Color(0xFF15803D), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.tr('Release Escrow Payout', 'एस्क्रो भुगतान प्राप्त करें'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr(
                'Ask the buyer for their 6-digit Delivery Handshake OTP shown on their AgriChain receipt upon handover.',
                'हैंडओवर पर खरीदार की एग्रीचेन रसीद पर प्रदर्शित 6-अंकीय डिलीवरी हैंडशेक ओटीपी मांगें।',
              ),
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                color: const Color(0xFF1B5E20),
              ),
              decoration: InputDecoration(
                hintText: '• • • • • •',
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 2),
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
              ),
            ),
            if (expectedOtp.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: Color(0xFF2563EB)),
                    const SizedBox(width: 6),
                    Text(
                      '${context.tr('Demo test OTP', 'डेमो टेस्ट ओटीपी')}: $expectedOtp',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.currency_rupee, color: Color(0xFF15803D), size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '${context.tr('Payout Amount', 'भुगतान राशि')}: ₹${total.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(context.tr('Cancel', 'रद्द करें'), style: const TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final entered = otpController.text.trim();
              if (expectedOtp.isNotEmpty && entered != expectedOtp) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.tr('❌ Incorrect OTP! Please verify with buyer.', '❌ गलत ओटीपी! कृपया खरीदार से पुष्टि करें।')),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              Navigator.pop(dialogCtx);

              await _dbService.updateRetailOrderStatus(
                orderId,
                'delivered',
                extra: {
                  'escrowStatus': 'RELEASED_TO_FARMER',
                  'deliveredAt': DateTime.now().toIso8601String(),
                },
              );

              if (context.mounted) {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    title: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 30),
                        const SizedBox(width: 10),
                        Text(context.tr('Escrow Released!', 'एस्क्रो जारी!')),
                      ],
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('🎉 Doorstep Handshake Verified via OTP!', '🎉 ओटीपी द्वारा डिलीवरी हैंडशेक सत्यापित!'),
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: const Color(0xFF15803D)),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.tr(
                            '₹${total.toStringAsFixed(0)} INR has been automatically released from the Polygon PoS Smart Escrow lock directly to your verified bank account.',
                            '₹${total.toStringAsFixed(0)} पॉलीगॉन पीओएस स्मार्ट एस्क्रो लॉक से सीधे आपके सत्यापित बैंक खाते में जमा कर दिया गया है।',
                          ),
                          style: const TextStyle(fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            'Polygon Tx: ${order['txHash'] ?? '0x9b12...c74a'}\nContract Status: FULFILLED',
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF475569)),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(context.tr('Done', 'पूर्ण'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(context.tr('Verify & Release', 'सत्यापित करें और प्राप्त करें'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }



  Widget _buildFarmerBulkDemandsTab(String farmerId, String farmerName) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _dbService.streamBulkRfqs(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen));
        }

        final rfqs = snapshot.data ?? [];

        if (rfqs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.hub_outlined,
                    size: 64,
                    color: AppTheme.textSecondary.withValues(alpha: 0.35),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.tr('No Active Bulk Demands Right Now', 'फिलहाल कोई सक्रिय थोक मांग नहीं है'),
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr(
                      'When bulk buyers and millers post large procurement orders, they will appear here so you can commit your harvested lot at fair guaranteed prices.',
                      'जब थोक खरीदार और मिल मालिक खरीद ऑर्डर पोस्ट करेंगे, तो वे यहां दिखाई देंगे ताकि आप गारंटीकृत उचित मूल्य पर फसल दे सकें।',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
          itemCount: rfqs.length,
          itemBuilder: (context, index) {
            final rfq = rfqs[index];
            return _buildFarmerDemandCard(rfq, farmerId, farmerName);
          },
        );
      },
    );
  }

  Widget _buildFarmerDemandCard(Map<String, dynamic> rfq, String farmerId, String farmerName) {
    final buyer = rfq['buyerName'] ?? rfq['companyName'] ?? 'AgroFoods Milling India';
    final crop = rfq['commodity'] ?? 'Wheat';
    final variety = rfq['variety'] ?? 'Premium Milling';
    final grade = rfq['qualityGrade'] ?? 'Grade A';
    final qtyQtl = (rfq['quantityQtl'] as num?)?.toDouble() ??
        ((rfq['requiredQuantityQtl'] as num?)?.toDouble() ?? 50.0);
    final targetPriceQtl = (rfq['targetPricePerQtl'] as num?)?.toDouble() ??
        ((rfq['maxPricePerQtl'] as num?)?.toDouble() ?? 3200.0);
    final pricePerKg = targetPriceQtl / 100.0;
    final location = rfq['deliveryLocation'] ?? 'Karnal Central Hub';
    final rfqId = rfq['id'] ?? 'RFQ-${DateTime.now().millisecondsSinceEpoch}';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.corporate_fare, size: 16, color: Color(0xFF15803D)),
                    const SizedBox(width: 6),
                    Text(
                      buyer,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    context.tr('VERIFIED BUYER', 'सत्यापित खरीदार'),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF15803D),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$crop ($variety)',
                          style: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.darkGreen,
                          ),
                        ),
                        Text(
                          '${context.tr('Required', 'आवश्यक')}: ${qtyQtl.toStringAsFixed(0)} Qtl (${(qtyQtl * 100).toStringAsFixed(0)} kg) • $grade',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${pricePerKg.toStringAsFixed(2)} / kg',
                          style: GoogleFonts.inter(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF2E7D32),
                          ),
                        ),
                        Text(
                          '₹${targetPriceQtl.toStringAsFixed(0)} / Qtl',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${context.tr('Delivery Terminal', 'वितरण केंद्र')}: $location',
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showFarmerParticipateModal(rfqId, farmerId, farmerName, crop, pricePerKg),
                    icon: const Icon(Icons.add_shopping_cart, size: 16),
                    label: Text(context.tr('Participate in Order / Supply Lot (लॉट से माल दें)', 'ऑर्डर में भाग लें / फसल लॉट दें')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFarmerParticipateModal(String rfqId, String farmerId, String farmerName, String crop, double pricePerKg) {
    final qtyCtrl = TextEditingController(text: '150');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${context.tr('Supply', 'आपूर्ति करें')} $crop ${context.tr('Lot', 'लॉट')}',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${context.tr('Buyer Guaranteed Rate', 'खरीदार गारंटीकृत दर')}: ₹${pricePerKg.toStringAsFixed(2)} / kg',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.tr('Quantity to contribute (kg)', 'योगदान मात्रा (किग्रा)'),
                border: const OutlineInputBorder(),
                suffixText: 'kg',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final qty = double.tryParse(qtyCtrl.text) ?? 150.0;
                  final totalEarnings = qty * pricePerKg;
                  Navigator.pop(ctx);
                  await _dbService.submitRfqQuote(rfqId, {
                    'farmerId': farmerId,
                    'farmerName': farmerName,
                    'offeredQuantityKg': qty,
                    'offeredPricePerKg': pricePerKg,
                    'totalEarnings': totalEarnings,
                    'status': 'FARMER_LOT_CONTRIBUTED',
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF1B5E20),
                        content: Text(
                          context.tr(
                            'Committed $qty kg of $crop! Total: ₹${totalEarnings.toStringAsFixed(0)}',
                            '$crop का $qty किग्रा समर्पित! कुल: ₹${totalEarnings.toStringAsFixed(0)}',
                          ),
                        ),
                      ),
                    );
                  }
                },
                child: Text(
                  context.tr('Confirm Lot Contribution (स्वीकारें)', 'लॉट योगदान की पुष्टि करें (स्वीकारें)'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

