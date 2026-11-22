import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../theme/app_theme.dart';
import '../../services/blockchain_service.dart';
import '../../services/database_service.dart';
import '../../services/multi_fpo_clustering_service.dart';
import '../../services/gemini_crop_assay_service.dart';
import '../../services/crop_image_validator_service.dart';
import '../../models/crop_benchmark_model.dart';
import '../../widgets/enhanced_app_bar.dart';
import '../../models/crop.dart';
import '../../utils/crop_image_helper.dart';
import '../../utils/translation_helper.dart';

enum CropAction { sell }

class AddCropScreen extends StatefulWidget {
  const AddCropScreen({super.key});

  @override
  State<AddCropScreen> createState() => _AddCropScreenState();
}

class _AddCropScreenState extends State<AddCropScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _quantityController = TextEditingController(text: '100 kg');
  final _priceController = TextEditingController();
  final _locationController = TextEditingController(
    text: 'Karnal Cluster, Haryana',
  );

  String? _selectedImagePath;
  XFile? _cropImageFile;
  XFile? _signatureImage;
  bool _isUploading = false;
  DateTime _harvestDate = DateTime.now();

  // Dynamic crop selection fields (auto-populated by AI image assaying or user dropdown)
  CropType? _selectedCropType;
  CropCategory? _selectedCategory;
  QualityGrade _selectedQualityGrade = QualityGrade.premium;
  final List<CertificationType> _selectedCertifications = [
    CertificationType.organic,
  ];
  CropPricing? _currentPricing;

  // AI Quality Assaying State
  bool _isAnalyzingWithAi = false;
  GeminiCropAssayResult? _aiAssayResult;

  // Selling Preference State: 'direct' (Direct Marketplace) or 'fpo' (Through an FPO)
  String _sellingMethod = 'direct';
  Map<String, dynamic>? _selectedFpo;
  bool _isLoadingFpos = false;
  List<Map<String, dynamic>> _discoveredFpos = [];
  final TextEditingController _fpoSearchController = TextEditingController();
  Position? _farmerPosition;
  bool _gpsPermissionDenied = false;
  bool _fpoConsentGiven = true;

  // Delivery & Logistics default state (Fulfillment is chosen post-order in My Orders)
  final String _deliveryOption = 'platform';
  final String _selectedLogisticsProvider = 'Delhivery B2B Reefer';
  final int _dispatchLeadTimeDays = 2;
  final TextEditingController _shippingNotesController =
      TextEditingController();

  // Pre-Harvest State: true (Standing crop in field) or false (Harvested ready)
  bool _isPreHarvest = false;
  int _daysToHarvest = 15;
  DateTime _estimatedHarvestDate = DateTime.now().add(const Duration(days: 15));
  String _cropGrowthStage = 'Grain Filling / Pod Formation';
  final double _preBookingAdvancePct = 20.0;
  final TextEditingController _daysToHarvestController = TextEditingController(
    text: '15',
  );

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _locationController.dispose();
    _fpoSearchController.dispose();
    _shippingNotesController.dispose();
    _daysToHarvestController.dispose();
    super.dispose();
  }

  /// Discover nearby verified FPOs using GPS device position with fallback
  Future<void> _fetchNearbyFpos() async {
    setState(() => _isLoadingFpos = true);

    double farmerLat = 29.6857; // Default GT belt Karnal coordinates
    double farmerLng = 76.9905;

    // 1. Try GPS location permission and position
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 4),
          ),
        );
        _farmerPosition = pos;
        farmerLat = pos.latitude;
        farmerLng = pos.longitude;
        _gpsPermissionDenied = false;
      } else {
        _gpsPermissionDenied = true;
      }
    } catch (e) {
      debugPrint('Location retrieval notice: $e');
      _gpsPermissionDenied = true;
    }

    // 2. Fetch verified active FPOs
    final clusterService = MultiFpoClusteringService();
    List<Map<String, dynamic>> rawFpos = [];

    try {
      final dbFpos = await DatabaseService().streamNearbyFpos().first.timeout(
        const Duration(seconds: 2),
        onTimeout: () => [],
      );
      if (dbFpos.isNotEmpty) {
        rawFpos.addAll(dbFpos);
      }
    } catch (_) {}

    // Verified FPO directory fallback network
    final verifiedDirectory = [
      {
        'id': 'fpo_karnal_01',
        'name': 'Karnal Agro Producer Co. Ltd.',
        'address': 'Karnal Central Agri Depot, Sector 4, Karnal, Haryana',
        'district': 'Karnal',
        'pincode': '132001',
        'lat': 29.6857,
        'lng': 76.9905,
        'isVerified': true,
        'commodities': ['Sharbati Wheat', 'Basmati Paddy', 'Mustard'],
      },
      {
        'id': 'fpo_taraori_02',
        'name': 'Taraori Kisan Producer Co. Ltd.',
        'address': 'Taraori Silo Bay, GT Road, Taraori, Karnal, Haryana',
        'district': 'Karnal',
        'pincode': '132116',
        'lat': 29.8010,
        'lng': 76.9230,
        'isVerified': true,
        'commodities': ['Basmati Paddy', 'Sharbati Wheat'],
      },
      {
        'id': 'fpo_gharaunda_03',
        'name': 'Gharaunda Farmers Producer Co. Ltd.',
        'address': 'Gharaunda Silo Complex, GT Road, Gharaunda, Haryana',
        'district': 'Karnal',
        'pincode': '132114',
        'lat': 29.5390,
        'lng': 76.9740,
        'isVerified': true,
        'commodities': ['Vegetables', 'Wheat', 'Paddy'],
      },
      {
        'id': 'fpo_kurukshetra_04',
        'name': 'Kurukshetra Organic FPO',
        'address': 'Kurukshetra Mega Yard, Kurukshetra, Haryana',
        'district': 'Kurukshetra',
        'pincode': '136118',
        'lat': 29.9695,
        'lng': 76.8783,
        'isVerified': true,
        'commodities': ['Organic Basmati', 'Wheat', 'Pulses'],
      },
      {
        'id': 'fpo_pehowa_05',
        'name': 'Pehowa Golden Grain FPO',
        'address': 'Pehowa Grain Terminal, Pehowa, Haryana',
        'district': 'Kurukshetra',
        'pincode': '136128',
        'lat': 29.9790,
        'lng': 76.5810,
        'isVerified': true,
        'commodities': ['Basmati Paddy', 'Maize', 'Sunflower'],
      },
    ];

    for (final clusterFpo in verifiedDirectory) {
      if (!rawFpos.any((f) => f['id'] == clusterFpo['id'])) {
        rawFpos.add(clusterFpo);
      }
    }

    // 3. Compute distance for each FPO and sort by proximity
    final fpoList = <Map<String, dynamic>>[];
    for (final f in rawFpos) {
      final fLat = (f['lat'] as num?)?.toDouble() ?? 29.6857;
      final fLng = (f['lng'] as num?)?.toDouble() ?? 76.9905;
      final dist = clusterService.calculateDistanceKm(
        farmerLat,
        farmerLng,
        fLat,
        fLng,
      );
      final item = Map<String, dynamic>.from(f);
      item['distanceKm'] = dist;
      fpoList.add(item);
    }

    fpoList.sort(
      (a, b) =>
          (a['distanceKm'] as double).compareTo(b['distanceKm'] as double),
    );

    if (mounted) {
      setState(() {
        _discoveredFpos = fpoList;
        _isLoadingFpos = false;
        if (_selectedFpo == null && _discoveredFpos.isNotEmpty) {
          _selectedFpo = _discoveredFpos.first;
        }
      });
    }
  }

  List<Map<String, dynamic>> get _filteredFpos {
    final query = _fpoSearchController.text.toLowerCase().trim();
    if (query.isEmpty) return _discoveredFpos;
    return _discoveredFpos.where((fpo) {
      final name = (fpo['name'] ?? '').toString().toLowerCase();
      final addr = (fpo['address'] ?? fpo['location'] ?? '')
          .toString()
          .toLowerCase();
      final dist = (fpo['district'] ?? '').toString().toLowerCase();
      final pin = (fpo['pincode'] ?? '').toString().toLowerCase();
      return name.contains(query) ||
          addr.contains(query) ||
          dist.contains(query) ||
          pin.contains(query);
    }).toList();
  }

  Future<void> _selectImage() async {
    final ImagePicker picker = ImagePicker();
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Upload Crop Sample Photo',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkGreen,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Take a photo of your harvested grain or choose an existing photo from gallery for AI assaying.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(ctx, ImageSource.camera),
                      icon: const Icon(
                        Icons.camera_alt,
                        color: Color(0xFF1B5E20),
                      ),
                      label: const Text(
                        'Camera',
                        style: TextStyle(
                          color: Color(0xFF1B5E20),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: const BorderSide(color: Color(0xFF1B5E20)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
                      icon: const Icon(
                        Icons.photo_library,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Gallery',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: const Color(0xFF1B5E20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    try {
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 800,
        maxHeight: 800,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();

        setState(() {
          _cropImageFile = image;
          _selectedImagePath = image.path;
          _isAnalyzingWithAi = true;
          _aiAssayResult = null;
        });

        // Run Multimodal Google Gemini 2.5 Flash Vision Assaying
        final inspection = await GeminiCropAssayService()
            .inspectAndAssayProduce(imageBytes: bytes, fileName: image.name);

        if (!inspection.isValidProduce) {
          if (mounted) {
            setState(() {
              _isAnalyzingWithAi = false;
              _cropImageFile = null;
              _selectedImagePath = null;
              _aiAssayResult = null;
            });
            _showInvalidCropImageDialog(
              CropValidationResult.invalid(
                reason:
                    inspection.rejectionReason ?? 'Non-crop image detected.',
                hindiReason:
                    inspection.hindiRejectionReason ??
                    'यह फोटो फसल की नहीं लग रही है।',
                detectedSubject: inspection.cropName,
              ),
            );
          }
          return;
        }

        // STRICT QUALITY GATE: Block produce with quality / purity < 50%
        if (inspection.purityScore < 50.0 || inspection.hasRotOrSpoilage) {
          if (mounted) {
            setState(() {
              _isAnalyzingWithAi = false;
              _cropImageFile = null;
              _selectedImagePath = null;
              _aiAssayResult = null;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '⚠️ AI जांच: पहचानी गई फसल (${inspection.cropName}) की गुणवत्ता केवल ${inspection.purityScore.toStringAsFixed(1)}% है (न्यूनतम 50% अनिवार्य)',
                ),
                backgroundColor: Colors.red.shade900,
                duration: const Duration(seconds: 5),
              ),
            );
            _showLowQualityRejectionDialog(
              purityScore: inspection.purityScore,
              cropName: inspection.cropName,
              reason: inspection.assessmentSummary,
            );
          }
          return;
        }

        if (mounted) {
          final assayResult = inspection.toAssayResult();
          final isSpoiled = inspection.hasRotOrSpoilage;

          setState(() {
            _aiAssayResult = assayResult;
            _isAnalyzingWithAi = false;

            // Automatically sync form to the crop detected by Gemini Vision
            _selectedCropType = inspection.detectedCropType;
            _selectedCategory = inspection.detectedCategory;
            _nameController.text = inspection.cropName;
            _descriptionController.text = inspection.description;
            _selectedQualityGrade = inspection.qualityGrade;

            _currentPricing = CropDataHelper.getPricingForCropType(
              inspection.detectedCropType,
            );
            if (_currentPricing != null && _currentPricing!.marketPrice > 0) {
              _priceController.text = (_currentPricing!.marketPrice / 100)
                  .toStringAsFixed(2);
            } else {
              final bm = CropBenchmark.findByName(inspection.cropName);
              if (bm != null && bm.mandiAvgPrice > 0) {
                _priceController.text = (bm.mandiAvgPrice / 100)
                    .toStringAsFixed(2);
              }
            }
            if (_quantityController.text.isEmpty) {
              _quantityController.text = '100 kg';
            }
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isSpoiled
                    ? '⚠️ Gemini Vision: सड़े/खराब लक्षण पाए गए (${inspection.agmarkGrade})'
                    : '✅ Gemini Vision: ${inspection.cropName} (${inspection.agmarkGrade}) सत्यापित!',
              ),
              backgroundColor: isSpoiled
                  ? Colors.red.shade800
                  : AppTheme.primaryGreen,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error picking crop image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick crop image: $e')),
        );
      }
    }
  }

  void _showInvalidCropImageDialog(CropValidationResult res) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cancel_outlined,
                color: Colors.red,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'अमान्य फोटो / Image Rejected',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade900,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    res.hindiMessage,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF991B1B),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    res.message,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '⚠️ जरूरी नियम (Produce Photo Rules):',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '• केवल खेत की कटी फसल या बोरियों के दानों का खुला सैंपल दिखाएं।',
              style: TextStyle(fontSize: 11.5, color: Colors.black87),
            ),
            const Text(
              '• किसी व्यक्ति, गाड़ी, चेहरे, स्क्रीनशॉट या सादे कागज़ की फोटो स्वीकार नहीं होगी।',
              style: TextStyle(fontSize: 11.5, color: Colors.black87),
            ),
            const Text(
              '• फोटो साफ और पर्याप्त रोशनी में खींची होनी चाहिए।',
              style: TextStyle(fontSize: 11.5, color: Colors.black87),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('समझ गया (Understood)'),
          ),
        ],
      ),
    );
  }

  void _showLowQualityRejectionDialog({
    required double purityScore,
    required String cropName,
    required String reason,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.red,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '🌾 $cropName: गुणवत्ता 50% से कम',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade900,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Prominent Detected Crop Header
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF87171)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.eco, color: Color(0xFFB91C1C), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'पहचानी गई फसल (Detected Crop): $cropName',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFB91C1C),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'गुणवत्ता स्कोर (Purity):',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade900,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${purityScore.toStringAsFixed(1)}% / 100%',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (purityScore / 100.0).clamp(0.0, 1.0),
                    backgroundColor: Colors.red.shade100,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '⚠️ AI Vision ने इस फोटो में "$cropName" की पहचान की है, लेकिन इसमें अत्यधिक फंगल सड़ांध (Fungal Rot / Mold) व खराबी पाई गई है।\n\nAgriChain नियमों के अनुसार 50% से कम शुद्धता वाली फसल ($cropName) को डिजिटल मंडी पर लिस्ट नहीं किया जा सकता।',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF991B1B),
                      height: 1.4,
                    ),
                  ),
                  if (reason.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      reason,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade800,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '💡 किसान के लिए सुधार सलाह (Quality Tips):',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '• दानों को अच्छी तरह छानकर धूल, खरपतवार और मिट्टी अलग करें।',
              style: TextStyle(fontSize: 11.5, color: Colors.black87),
            ),
            const Text(
              '• धूप में सुखाकर नमी की मात्रा 12% से नीचे लाएं।',
              style: TextStyle(fontSize: 11.5, color: Colors.black87),
            ),
            const Text(
              '• सड़े या दागदार दानों को अलग करने के बाद नई फोटो अपलोड करें।',
              style: TextStyle(fontSize: 11.5, color: Colors.black87),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('समझ गया (Understood)'),
          ),
        ],
      ),
    );
  }

  void _showAutoAiAssayPromptDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: AppTheme.primaryGreen),
            const SizedBox(width: 8),
            Text(
              'Automated AI Crop Assaying',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Grain sample photo captured! AI will now automatically analyze your crop sample for:',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.grey.shade800,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            _buildAssayPoint('Moisture % (Optimal ≤ 12.0%)'),
            _buildAssayPoint('Broken Grain % (Grade A ≤ 3.0%)'),
            _buildAssayPoint('Foreign Matter & Seed Purity Index'),
            _buildAssayPoint('AGMARK Quality Grade Certification'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                '🔒 Listing Gate: You can publish your crop only after AI assay verification is complete.',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppTheme.darkGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _runAiAssaying();
            },
            icon: const Icon(Icons.flash_on, size: 16),
            label: const Text('Start Auto AI Assaying'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssayPoint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle,
            color: AppTheme.primaryGreen,
            size: 15,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runAiAssaying() async {
    if (_cropImageFile == null) return;

    setState(() => _isAnalyzingWithAi = true);

    try {
      final bytes = await _cropImageFile!.readAsBytes();
      final inspection = await GeminiCropAssayService().inspectAndAssayProduce(
        imageBytes: bytes,
        fileName: _cropImageFile!.name,
      );

      if (!inspection.isValidProduce) {
        throw CropValidationException(
          message: inspection.rejectionReason ?? 'Non-crop image detected.',
          hindiMessage:
              inspection.hindiRejectionReason ??
              'यह फोटो फसल की नहीं लग रही है।',
          title: 'अमान्य फोटो / Image Rejected',
        );
      }

      // STRICT QUALITY THRESHOLD GATE (< 50% PURITY)
      if (inspection.purityScore < 50.0 || inspection.hasRotOrSpoilage) {
        throw CropValidationException(
          message:
              'Crop purity/quality score is ${inspection.purityScore.toStringAsFixed(1)}%, which is below the minimum required 50% threshold.',
          hindiMessage:
              'फसल की गुणवत्ता व शुद्धता केवल ${inspection.purityScore.toStringAsFixed(1)}% है (न्यूनतम 50% आवश्यक)। 50% से कम गुणवत्ता वाली फसल AgriChain पर लिस्ट नहीं की जा सकती।',
          title: 'गुणवत्ता 50% से कम / Quality Below 50%',
        );
      }

      final result = inspection.toAssayResult();

      if (mounted) {
        final bool isSpoiled = inspection.hasRotOrSpoilage;

        setState(() {
          _aiAssayResult = result;
          _isAnalyzingWithAi = false;
          _selectedCropType = inspection.detectedCropType;
          _selectedCategory = inspection.detectedCategory;
          _nameController.text = inspection.cropName;
          _descriptionController.text = inspection.description;
          _selectedQualityGrade = inspection.qualityGrade;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isSpoiled
                  ? '⚠️ Gemini Vision: सड़े/खराब लक्षण पाए गए (${result.agmarkGrade})'
                  : '✅ Gemini Vision: ${inspection.cropName} (${result.agmarkGrade}) सत्यापित!',
            ),
            backgroundColor: isSpoiled
                ? Colors.red.shade800
                : AppTheme.primaryGreen,
          ),
        );
      }
    } catch (e) {
      debugPrint('AI Assaying error: $e');
      if (mounted) {
        setState(() {
          _isAnalyzingWithAi = false;
          _cropImageFile = null;
          _selectedImagePath = null;
          _aiAssayResult = null;
        });

        if (e is CropValidationException) {
          _showInvalidCropImageDialog(
            CropValidationResult.invalid(
              reason: e.message,
              hindiReason: e.hindiMessage,
              detectedSubject: 'Non-crop / Document Detected',
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('AI Assaying error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _pickSignatureImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1024,
      );

      if (image != null) {
        setState(() {
          _signatureImage = image;
        });
      }
    } catch (e) {
      debugPrint('Error picking signature image: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
      }
    }
  }

  Future<void> _selectHarvestDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _harvestDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryGreen,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _harvestDate) {
      setState(() {
        _harvestDate = picked;
      });
    }
  }

  void _onCropTypeChanged(CropType? cropType) {
    setState(() {
      _selectedCropType = cropType;
      if (cropType != null) {
        _selectedCategory = CropDataHelper.getCategoryForCropType(cropType);
        _currentPricing = CropDataHelper.getPricingForCropType(cropType);
        if (_nameController.text.isEmpty) {
          _nameController.text = CropDataHelper.getCropDisplayName(cropType);
        }
      } else {
        _selectedCategory = null;
        _currentPricing = null;
      }
    });
  }

  void _toggleCertification(CertificationType certification) {
    setState(() {
      if (_selectedCertifications.contains(certification)) {
        _selectedCertifications.remove(certification);
      } else {
        _selectedCertifications.add(certification);
      }
    });
  }

  Widget _buildPricingInfo() {
    final cropText = _nameController.text.trim();
    final bm = CropBenchmark.findByName(
      cropText.isNotEmpty ? cropText : (_selectedCropType?.name ?? 'wheat'),
    );

    if (bm == null && _currentPricing == null) return const SizedBox.shrink();

    final msp = bm?.mspPerQtl ?? _currentPricing?.msp.toDouble() ?? 2275.0;
    final mandiMin = bm?.mandiMinPrice ?? (msp * 1.05);
    final mandiMax = bm?.mandiMaxPrice ?? (msp * 1.25);
    final mandiAvg = bm?.mandiAvgPrice ?? (msp * 1.15);
    final hindi = bm?.hindiName ?? 'फसल';

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.price_check,
                color: AppTheme.darkGreen,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'सरकारी समर्थन मूल्य (MSP) व मंडी भाव • $hindi',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.darkGreen,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: const Text(
                  'MSP 2024-25',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF15803D),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Govt MSP Card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Govt. MSP (न्यूनतम भाव):',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF065F46),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₹${msp.toInt()} / क्विंटल',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF047857),
                        ),
                      ),
                      Text(
                        '≈ ₹${(msp / 100).toStringAsFixed(1)} / किलो',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Mandi Average
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFED7AA)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'मंडी औसत (Market Avg):',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9A3412),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₹${mandiAvg.toInt()} / क्विंटल',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFC2410C),
                        ),
                      ),
                      Text(
                        'रेंज: ₹${mandiMin.toInt()} - ₹${mandiMax.toInt()}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: const [
                Icon(Icons.info_outline, size: 14, color: Color(0xFFB45309)),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '💡 किसान सलाह: अपनी फसल को सरकारी MSP से कम दाम पर कभी लिस्ट न करें।',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF92400E),
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

  Future<void> _uploadCrop() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedImagePath == null || _cropImageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ फसल का फोटो लगाना अनिवार्य है (Crop photo is compulsory). बिना फोटो के फसल लिस्ट नहीं की जा सकती।',
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    if (_aiAssayResult == null) {
      _showAutoAiAssayPromptDialog();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ AI Assaying Required: Please run automated AI quality assay first.',
          ),
          backgroundColor: Colors.deepOrange,
        ),
      );
      return;
    }

    // STRICT QUALITY GATE: Cannot list produce with quality / purity < 50%
    if (_aiAssayResult!.purityScore < 50.0) {
      _showLowQualityRejectionDialog(
        purityScore: _aiAssayResult!.purityScore,
        cropName: _nameController.text.isNotEmpty
            ? _nameController.text
            : 'Crop',
        reason: _aiAssayResult!.assessmentSummary,
      );
      return;
    }

    final isSpoiled =
        _aiAssayResult != null &&
        (_aiAssayResult!.agmarkGrade.contains('REJECTED') ||
            _aiAssayResult!.agmarkGrade.contains('SUB-STANDARD') ||
            !_aiAssayResult!.isMspCompliant);

    if (isSpoiled && _selectedQualityGrade == QualityGrade.premium) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ गुणवत्ता त्रुटि: सड़े/खराब माल को प्रीमियम ग्रेड में लिस्ट नहीं किया जा सकता। कृपया ग्रेड को "Sub-standard" चुनें।',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_sellingMethod == 'fpo') {
      if (_selectedFpo == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⚠️ कृपया अपनी फसल बेचने के लिए एक निकटतम एफपीओ (FPO) का चयन करें।',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }
      if (!_fpoConsentGiven) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⚠️ कृपया एफपीओ के साथ किसान विवरण साझा करने की सहमति दें।',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final blockchainService = BlockchainService();

      // Step 1: Upload image to IPFS
      final ipfsHash = await blockchainService.uploadImageToIPFS(
        _selectedImagePath ?? 'ipfs_hash_default',
      );

      // Step 2: Mint NFT for the crop
      final nftTokenId = await blockchainService.mintNFT(
        appState.currentUser?.name ?? 'Ramesh Kumar',
        _nameController.text,
        _descriptionController.text,
        ipfsHash,
      );

      String? cropSignatureUrl;
      if (_signatureImage != null) {
        try {
          final bytes = await _signatureImage!.readAsBytes();
          final base64String = base64Encode(bytes);
          cropSignatureUrl = 'data:image/jpeg;base64,$base64String';
        } catch (e) {
          debugPrint('Error converting crop signature: $e');
        }
      }

      String cropImageUrl = _selectedImagePath ?? '';
      if (_cropImageFile != null) {
        try {
          final bytes = await _cropImageFile!.readAsBytes();
          final base64String = base64Encode(bytes);
          cropImageUrl = 'data:image/jpeg;base64,$base64String';
        } catch (e) {
          debugPrint('Error converting crop image: $e');
        }
      }
      if (cropImageUrl.isEmpty) {
        cropImageUrl = CropImageHelper.getContextualCropImageUrl(
          _nameController.text,
        );
      }

      // Step 3: Create crop using AppState
      final success = await appState.createCrop(
        name: _nameController.text,
        location: _locationController.text.isEmpty
            ? appState.currentUser?.location ?? 'Karnal Cluster, Haryana'
            : _locationController.text,
        price: double.parse(_priceController.text),
        quantity: _quantityController.text,
        harvestDate: _harvestDate,
        imageUrl: cropImageUrl,
        description: _descriptionController.text,
        cropType: _selectedCropType ?? CropType.wheat,
        category: _selectedCategory ?? CropCategory.grains,
        qualityGrade: _selectedQualityGrade,
        isNFT: true,
        biddingType: BiddingType.fixedPrice,
        signatureUrl: cropSignatureUrl,
        sellingMethod: _sellingMethod,
        fpoId: (_sellingMethod == 'fpo' && _selectedFpo != null)
            ? _selectedFpo!['id'] as String?
            : null,
        fpoName: (_sellingMethod == 'fpo' && _selectedFpo != null)
            ? _selectedFpo!['name'] as String?
            : null,
        fpoConsentGiven: _fpoConsentGiven,
        deliveryOption: _deliveryOption,
        logisticsProvider: _deliveryOption == 'platform'
            ? _selectedLogisticsProvider
            : 'Self-Arranged (Farmer Transport)',
        dispatchLeadTimeDays: _dispatchLeadTimeDays,
        shippingNotes: _shippingNotesController.text.trim().isNotEmpty
            ? _shippingNotesController.text.trim()
            : null,
        isPreHarvest: _isPreHarvest,
        daysToHarvest: _isPreHarvest ? _daysToHarvest : null,
        estimatedHarvestDate: _isPreHarvest ? _estimatedHarvestDate : null,
        cropGrowthStage: _isPreHarvest ? _cropGrowthStage : null,
        preBookingAdvancePct: _isPreHarvest ? _preBookingAdvancePct : null,
      );

      if (success) {
        debugPrint('✅ Crop created successfully');
        final cropId = DateTime.now().millisecondsSinceEpoch.toString();
        await blockchainService.createSellOrder(
          cropId,
          double.parse(_priceController.text),
          _quantityController.text,
          nftTokenId,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _sellingMethod == 'fpo'
                  ? '🌾 फसल सफलतापूर्वक ${_selectedFpo?['name'] ?? 'FPO'} के माध्यम से लिस्ट हो गई! एफपीओ को विवरण भेज दिया गया है।'
                  : '🌾 Crop listing published successfully! Live in buyer marketplace.',
            ),
            backgroundColor: const Color(0xFF1B5E20),
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAssayVerified =
        _aiAssayResult != null &&
        _cropImageFile != null &&
        _aiAssayResult!.purityScore >= 50.0;

    return Scaffold(
      appBar: const EnhancedAppBar(
        title: 'Add New Crop',
        subtitle: 'List your crop for sale on AgriChain',
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Selling Preference Section (Directly on Marketplace vs Through an FPO)
              _buildSellingPreferenceSection(),
              const SizedBox(height: 24),

              // Pre-Harvest Standing Crop vs Ready Harvest Section
              _buildPreHarvestSection(),
              const SizedBox(height: 24),

              // Image Upload
              const Text(
                'Crop Image',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.darkGreen,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _selectImage,
                child: Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: _selectedImagePath == null
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_a_photo,
                              size: 48,
                              color: AppTheme.grey,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Tap to select crop sample image',
                              style: TextStyle(
                                color: AppTheme.grey,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        )
                      : Stack(
                          children: [
                            Container(
                              width: double.infinity,
                              height: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: AppTheme.primaryGreen.withValues(
                                  alpha: 0.1,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: _cropImageFile != null
                                    ? (kIsWeb
                                          ? Image.network(
                                              _cropImageFile!.path,
                                              fit: BoxFit.cover,
                                            )
                                          : Image.file(
                                              File(_cropImageFile!.path),
                                              fit: BoxFit.cover,
                                            ))
                                    : const Icon(
                                        Icons.image,
                                        size: 64,
                                        color: AppTheme.primaryGreen,
                                      ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: isAssayVerified
                                      ? AppTheme.primaryGreen
                                      : Colors.orange,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isAssayVerified
                                      ? Icons.check
                                      : Icons.auto_awesome,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              // AI ASSAYING SCANNER / RESULT CARD
              if (_isAnalyzingWithAi) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF81C784)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'AI Assaying analyzing moisture %, broken grains %, foreign matter & AGMARK grade...',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppTheme.darkGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_aiAssayResult != null && !_isAnalyzingWithAi) ...[
                const SizedBox(height: 14),
                Builder(
                  builder: (context) {
                    final isRejected =
                        _aiAssayResult!.agmarkGrade.contains('REJECTED') ||
                        _aiAssayResult!.agmarkGrade.contains('SUB-STANDARD') ||
                        !_aiAssayResult!.isMspCompliant;

                    return Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isRejected
                                  ? const [Color(0xFF450A0A), Color(0xFF7F1D1D)]
                                  : const [
                                      Color(0xFF0F381E),
                                      Color(0xFF1B5E20),
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (isRejected
                                            ? Colors.red
                                            : const Color(0xFF1B5E20))
                                        .withValues(alpha: 0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        isRejected
                                            ? Icons.warning_amber_rounded
                                            : Icons.auto_awesome,
                                        color: isRejected
                                            ? const Color(0xFFFCA5A5)
                                            : const Color(0xFF69F0AE),
                                        size: 18,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'AI Crop Assaying Results',
                                        style: GoogleFonts.outfit(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isRejected
                                          ? const Color(0xFFF87171)
                                          : const Color(0xFF69F0AE),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      _aiAssayResult!.agmarkGrade,
                                      style: GoogleFonts.inter(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        color: isRejected
                                            ? Colors.white
                                            : const Color(0xFF0F381E),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  _buildAssayMetricCol(
                                    isRejected ? 'Moisture/Decay' : 'Moisture',
                                    '${_aiAssayResult!.moisturePercentage}%',
                                    isRejected
                                        ? 'Critical Rot'
                                        : 'Optimal <12%',
                                  ),
                                  _buildAssayMetricCol(
                                    isRejected
                                        ? 'Defect/Rot %'
                                        : 'Broken Grain',
                                    '${_aiAssayResult!.brokenGrainPercentage}%',
                                    isRejected ? 'Severe Decay' : 'Grade A <3%',
                                  ),
                                  _buildAssayMetricCol(
                                    isRejected
                                        ? 'Fungal Residue'
                                        : 'Foreign Matter',
                                    '${_aiAssayResult!.foreignMatterPercentage}%',
                                    isRejected
                                        ? 'Mold Infested'
                                        : 'Clean <0.5%',
                                  ),
                                  _buildAssayMetricCol(
                                    'AI Purity',
                                    '${_aiAssayResult!.purityScore}%',
                                    isRejected
                                        ? 'Failed Standard'
                                        : 'High Purity',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _aiAssayResult!.assessmentSummary,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: Colors.white70,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isRejected) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.red.shade300),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.cancel,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '⚠️ गुणवत्ता चेतावनी (Quality Warning): फोटो में सड़ी/खराब फसल (Fungal Rot & Decay) पाई गई है। ऐसी फसल प्रीमियम में नहीं बिक सकती और इसका ग्रेड "Sub-standard / Rejected" कर दिया गया है।',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.red.shade900,
                                      fontWeight: FontWeight.w600,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 24),

              // Crop Details
              const Text(
                'Crop Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.darkGreen,
                ),
              ),
              const SizedBox(height: 16),

              // Crop Name
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Crop Name',
                  hintText: 'e.g., Organic Wheat',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppTheme.primaryGreen,
                      width: 2,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter crop name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Crop Type Dropdown
              DropdownButtonFormField<CropType>(
                value: _selectedCropType,
                decoration: InputDecoration(
                  labelText: 'Crop Type',
                  hintText: 'Select crop type',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppTheme.primaryGreen,
                      width: 2,
                    ),
                  ),
                ),
                items: CropDataHelper.cropCategories.entries
                    .expand(
                      (categoryEntry) => [
                        DropdownMenuItem<CropType>(
                          enabled: false,
                          value: null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              CropDataHelper.getCategoryDisplayName(
                                categoryEntry.key,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.darkGreen,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        ...categoryEntry.value.map(
                          (cropType) => DropdownMenuItem<CropType>(
                            value: cropType,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: Text(
                                CropDataHelper.getCropDisplayName(cropType),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                    .toList(),
                onChanged: _onCropTypeChanged,
                validator: (value) {
                  if (value == null) {
                    return 'Please select a crop type';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Show pricing info if crop type is selected
              _buildPricingInfo(),

              // Quality Grade Dropdown
              DropdownButtonFormField<QualityGrade>(
                value: _selectedQualityGrade,
                decoration: InputDecoration(
                  labelText: 'Quality Grade',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppTheme.primaryGreen,
                      width: 2,
                    ),
                  ),
                ),
                items: QualityGrade.values
                    .map(
                      (grade) => DropdownMenuItem<QualityGrade>(
                        value: grade,
                        child: Text(
                          CropDataHelper.getQualityGradeDisplayName(grade),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedQualityGrade = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),

              // Certifications
              const Text(
                'Certifications',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.darkGreen,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: CertificationType.values.map((certification) {
                  final isSelected = _selectedCertifications.contains(
                    certification,
                  );
                  return FilterChip(
                    label: Text(
                      CropDataHelper.getCertificationDisplayName(certification),
                    ),
                    selected: isSelected,
                    onSelected: (_) => _toggleCertification(certification),
                    selectedColor: AppTheme.primaryGreen.withValues(alpha: 0.2),
                    checkmarkColor: AppTheme.primaryGreen,
                    backgroundColor: Colors.grey[100],
                    labelStyle: TextStyle(
                      color: isSelected ? AppTheme.primaryGreen : AppTheme.grey,
                      fontWeight: isSelected
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Description
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Description',
                  hintText: 'Describe your crop quality, farming methods, etc.',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppTheme.primaryGreen,
                      width: 2,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter description';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Quantity (in kg)
              TextFormField(
                controller: _quantityController,
                decoration: InputDecoration(
                  labelText: 'Quantity (in kg)',
                  hintText: 'e.g., 500 kg',
                  helperText: 'Available harvest volume in kilograms',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppTheme.primaryGreen,
                      width: 2,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Enter quantity';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Price Field (Price per kg)
              TextFormField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Price per kg (₹)',
                  hintText: 'e.g., 35.00',
                  helperText: 'Selling price per kilogram in Rupees',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppTheme.primaryGreen,
                      width: 2,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Enter price';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Enter valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Location
              TextFormField(
                controller: _locationController,
                decoration: InputDecoration(
                  labelText: 'Location (Optional)',
                  hintText: 'Farm location',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppTheme.primaryGreen,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Harvest Date
              GestureDetector(
                onTap: _selectHarvestDate,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: AppTheme.grey),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Harvest Date',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.grey,
                            ),
                          ),
                          Text(
                            '${_harvestDate.day}/${_harvestDate.month}/${_harvestDate.year}',
                            style: const TextStyle(
                              fontSize: 16,
                              color: AppTheme.darkGreen,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Signature Upload Section
              const Text(
                'Contract Document Signature',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.darkGreen,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    if (_signatureImage != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: kIsWeb
                            ? Image.network(
                                _signatureImage!.path,
                                height: 100,
                                width: double.infinity,
                                fit: BoxFit.contain,
                              )
                            : Image.file(
                                File(_signatureImage!.path),
                                height: 100,
                                width: double.infinity,
                                fit: BoxFit.contain,
                              ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _pickSignatureImage,
                        icon: const Icon(
                          Icons.edit,
                          color: AppTheme.primaryGreen,
                        ),
                        label: const Text('Change Signature'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryGreen,
                          side: const BorderSide(color: AppTheme.primaryGreen),
                        ),
                      ),
                    ] else ...[
                      const Icon(Icons.draw, size: 48, color: AppTheme.grey),
                      const SizedBox(height: 8),
                      const Text(
                        'Upload your signature for contracts associated with this crop',
                        style: TextStyle(color: AppTheme.grey),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _pickSignatureImage,
                        icon: const Icon(
                          Icons.upload,
                          color: AppTheme.primaryGreen,
                        ),
                        label: const Text('Upload Signature'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryGreen,
                          side: const BorderSide(color: AppTheme.primaryGreen),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isUploading ? null : _uploadCrop,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isAssayVerified
                        ? AppTheme.primaryGreen
                        : Colors.grey.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isUploading
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('Creating NFT & Processing...'),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isAssayVerified
                                  ? Icons.verified
                                  : Icons.lock_outline,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isAssayVerified
                                  ? 'List Crop for Sale (Verified)'
                                  : (_cropImageFile == null
                                        ? 'Add Crop Photo to List (Compulsory)'
                                        : 'Complete AI Assaying (≥50% Quality) to List'),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // NFT Info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.security, color: AppTheme.primaryGreen),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your crop will be automatically converted to an NFT for blockchain verification and ownership proof.',
                        style: TextStyle(
                          color: AppTheme.darkGreen,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssayMetricCol(String title, String val, String sub) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(fontSize: 9, color: Colors.white60),
          ),
          const SizedBox(height: 2),
          Text(
            val,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            sub,
            style: GoogleFonts.inter(
              fontSize: 8,
              color: const Color(0xFF69F0AE),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSellingPreferenceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr(
            'How would you like to sell your produce?',
            'आप अपनी उपज कैसे बेचना चाहते हैं?',
          ),
          style: GoogleFonts.outfit(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppTheme.darkGreen,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr(
            'Choose direct sale under your name, or route through an accredited FPO for collective aggregation.',
            'अपनी फसल सीधे अपने नाम पर बेचें या सामूहिक विपणन व सरकारी लाभ हेतु निकटतम एफपीओ चुनें।',
          ),
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 14),

        // Two option cards
        Row(
          children: [
            // Option 1: Directly on Marketplace
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _sellingMethod = 'direct';
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _sellingMethod == 'direct'
                        ? const Color(0xFFF0FDF4)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _sellingMethod == 'direct'
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFCBD5E1),
                      width: _sellingMethod == 'direct' ? 2 : 1,
                    ),
                    boxShadow: _sellingMethod == 'direct'
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFF16A34A,
                              ).withValues(alpha: 0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _sellingMethod == 'direct'
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFF1F5F9),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.storefront_outlined,
                              size: 20,
                              color: _sellingMethod == 'direct'
                                  ? const Color(0xFF15803D)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                          Icon(
                            _sellingMethod == 'direct'
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: _sellingMethod == 'direct'
                                ? const Color(0xFF16A34A)
                                : const Color(0xFF94A3B8),
                            size: 20,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        context.tr(
                          'Directly on Marketplace',
                          'सीधे मार्केटप्लेस पर',
                        ),
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _sellingMethod == 'direct'
                              ? const Color(0xFF15803D)
                              : const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.tr(
                          'Listed under your own farmer profile directly to buyers.',
                          'सीधे आपके अपने नाम से खरीदारों को प्रदर्शित होगी।',
                        ),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Option 2: Through an FPO
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _sellingMethod = 'fpo';
                  });
                  if (_discoveredFpos.isEmpty && !_isLoadingFpos) {
                    _fetchNearbyFpos();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _sellingMethod == 'fpo'
                        ? const Color(0xFFEFF6FF)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _sellingMethod == 'fpo'
                          ? const Color(0xFF2563EB)
                          : const Color(0xFFCBD5E1),
                      width: _sellingMethod == 'fpo' ? 2 : 1,
                    ),
                    boxShadow: _sellingMethod == 'fpo'
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFF2563EB,
                              ).withValues(alpha: 0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _sellingMethod == 'fpo'
                                  ? const Color(0xFFDBEAFE)
                                  : const Color(0xFFF1F5F9),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.apartment,
                              size: 20,
                              color: _sellingMethod == 'fpo'
                                  ? const Color(0xFF1D4ED8)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                          Icon(
                            _sellingMethod == 'fpo'
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: _sellingMethod == 'fpo'
                                ? const Color(0xFF2563EB)
                                : const Color(0xFF94A3B8),
                            size: 20,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        context.tr('Through an FPO', 'एफपीओ के माध्यम से'),
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _sellingMethod == 'fpo'
                              ? const Color(0xFF1D4ED8)
                              : const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.tr(
                          'Listed under verified FPO for bulk procurement & DBT.',
                          'एफपीओ के नाम से लिस्ट होगी, थोक खरीद व सीधा बैंक भुगतान।',
                        ),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        // DYNAMIC FPO DISCOVERY SECTION (Shown ONLY when Through an FPO is selected)
        if (_sellingMethod == 'fpo') ...[
          const SizedBox(height: 18),
          _buildFpoDiscoverySection(),
        ],
      ],
    );
  }

  Widget _buildFpoDiscoverySection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.location_searching,
                    size: 18,
                    color: Color(0xFF1D4ED8),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    context.tr('Nearby Verified FPOs', 'निकटतम सत्यापित एफपीओ'),
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: _fetchNearbyFpos,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.refresh,
                        size: 14,
                        color: Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        context.tr('Refresh GPS', 'स्थान रीफ्रेश करें'),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // GPS / Location Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _gpsPermissionDenied
                  ? const Color(0xFFFEF3C7)
                  : const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _gpsPermissionDenied ? Icons.location_off : Icons.my_location,
                  size: 13,
                  color: _gpsPermissionDenied
                      ? const Color(0xFF92400E)
                      : const Color(0xFF166534),
                ),
                const SizedBox(width: 5),
                Text(
                  _gpsPermissionDenied
                      ? context.tr(
                          'GPS Disabled • Using Region & Manual Search',
                          'जीपीएस बंद • क्षेत्रीय व हस्तचालित खोज सक्रिय',
                        )
                      : (_farmerPosition != null
                            ? '${context.tr('GPS Active', 'जीपीएस सक्रिय')} (${_farmerPosition!.latitude.toStringAsFixed(2)}, ${_farmerPosition!.longitude.toStringAsFixed(2)})'
                            : context.tr(
                                'GPS Location Active (Sorted Closest First)',
                                'जीपीएस सक्रिय (निकटतम एफपीओ पहले)',
                              )),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _gpsPermissionDenied
                        ? const Color(0xFF92400E)
                        : const Color(0xFF166534),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Manual Location Search Fallback
          TextField(
            controller: _fpoSearchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              hintText: context.tr(
                'Search by village, district, or PIN code...',
                'गांव, जिला या पिन कोड से खोजें...',
              ),
              hintStyle: const TextStyle(
                fontSize: 12,
                color: Color(0xFF94A3B8),
              ),
              prefixIcon: const Icon(
                Icons.search,
                size: 18,
                color: Color(0xFF64748B),
              ),
              suffixIcon: _fpoSearchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _fpoSearchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF2563EB)),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // FPO List or Loading
          if (_isLoadingFpos)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            )
          else if (_filteredFpos.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: Column(
                children: [
                  const Icon(
                    Icons.location_off_outlined,
                    size: 36,
                    color: Color(0xFF94A3B8),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr(
                      'No FPOs found matching your search.',
                      'आपकी खोज से मेल खाता कोई एफपीओ नहीं मिला।',
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      _fpoSearchController.clear();
                      _fetchNearbyFpos();
                    },
                    child: Text(
                      context.tr(
                        'Reset & Show All FPOs',
                        'रीसेट करें और सभी एफपीओ देखें',
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _filteredFpos.length,
              itemBuilder: (context, index) {
                final fpo = _filteredFpos[index];
                final isSelected = _selectedFpo?['id'] == fpo['id'];
                final distKm = (fpo['distanceKm'] as num?)?.toDouble() ?? 0.0;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedFpo = fpo;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFF0FDF4)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFE2E8F0),
                        width: isSelected ? 1.8 : 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: isSelected
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF94A3B8),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      fpo['name'] ?? 'FPO',
                                      style: GoogleFonts.outfit(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected
                                            ? const Color(0xFF15803D)
                                            : const Color(0xFF1E293B),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '✓ Verified FPO',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF15803D),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                fpo['address'] ??
                                    fpo['location'] ??
                                    'Haryana GT Belt',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF64748B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEEF2FF),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '📍 ${distKm.toStringAsFixed(1)} km away',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF4338CA),
                                      ),
                                    ),
                                  ),
                                  if (fpo['district'] != null) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '• Dist: ${fpo['district']}',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          const SizedBox(height: 10),
          // Privacy & Consent Checkbox
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _fpoConsentGiven,
                  onChanged: (val) =>
                      setState(() => _fpoConsentGiven = val ?? true),
                  activeColor: const Color(0xFF16A34A),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.tr(
                      'I consent to share my farmer profile, contact details, and registered bank details securely with this selected FPO for consignment tracking and direct DBT payout.',
                      'मैं सहमति देता/देती हूँ कि मेरी किसान प्रोफाइल, संपर्क और पंजीकृत बैंक खाते का विवरण इस चयनित एफपीओ के साथ सुरक्षित रूप से साझा किया जाए।',
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF92400E),
                      height: 1.3,
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

  /// Crop Readiness & Pre-Harvest Booking Section
  Widget _buildPreHarvestSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                context.tr(
                  'Crop Readiness & Pre-Harvest Booking',
                  'फसल उपलब्धता एवं प्री-हार्वेस्ट बुकिंग',
                ),
                style: GoogleFonts.outfit(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkGreen,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _isPreHarvest
                    ? const Color(0xFFF3E8FF)
                    : const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _isPreHarvest
                      ? const Color(0xFFC084FC)
                      : const Color(0xFF86EFAC),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isPreHarvest ? Icons.grass : Icons.inventory_2_outlined,
                    size: 13,
                    color: _isPreHarvest
                        ? const Color(0xFF7E22CE)
                        : const Color(0xFF15803D),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isPreHarvest ? 'Standing Crop' : 'Harvested Ready',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: _isPreHarvest
                          ? const Color(0xFF7E22CE)
                          : const Color(0xFF15803D),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          context.tr(
            'Is this crop currently standing in the field? Buyers can pre-book your upcoming harvest in advance at a locked guaranteed price.',
            'क्या यह फसल अभी खेत में खड़ी है? खरीदार कटाई से पहले ही आपकी फसल की अग्रिम प्री-बुकिंग (Pre-book) कर सकते हैं।',
          ),
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 14),

        // Two option cards
        Row(
          children: [
            // Option 1: Harvested & Ready for Sale
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _isPreHarvest = false;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: !_isPreHarvest
                        ? const Color(0xFFF0FDF4)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: !_isPreHarvest
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFCBD5E1),
                      width: !_isPreHarvest ? 2 : 1,
                    ),
                    boxShadow: !_isPreHarvest
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFF16A34A,
                              ).withValues(alpha: 0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: !_isPreHarvest
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFF1F5F9),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.inventory_2_outlined,
                              size: 20,
                              color: !_isPreHarvest
                                  ? const Color(0xFF15803D)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                          Icon(
                            !_isPreHarvest
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: !_isPreHarvest
                                ? const Color(0xFF16A34A)
                                : const Color(0xFF94A3B8),
                            size: 20,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        context.tr('Harvested & Ready', 'कटी हुई तैयार फसल'),
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: !_isPreHarvest
                              ? const Color(0xFF15803D)
                              : const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Immediate Dispatch',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF15803D),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.tr(
                          'Produce is harvested and ready for dispatch upon buyer purchase.',
                          'फसल तैयार है, ऑर्डर मिलते ही प्रेषण के लिए उपलब्ध।',
                        ),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Option 2: Pre-Harvesting / Standing Crop
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _isPreHarvest = true;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _isPreHarvest
                        ? const Color(0xFFFAF5FF)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _isPreHarvest
                          ? const Color(0xFF9333EA)
                          : const Color(0xFFCBD5E1),
                      width: _isPreHarvest ? 2 : 1,
                    ),
                    boxShadow: _isPreHarvest
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFF9333EA,
                              ).withValues(alpha: 0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _isPreHarvest
                                  ? const Color(0xFFF3E8FF)
                                  : const Color(0xFFF1F5F9),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.grass,
                              size: 20,
                              color: _isPreHarvest
                                  ? const Color(0xFF7E22CE)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                          Icon(
                            _isPreHarvest
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: _isPreHarvest
                                ? const Color(0xFF9333EA)
                                : const Color(0xFF94A3B8),
                            size: 20,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        context.tr(
                          'Pre-Harvesting',
                          'खेत में खड़ी (प्री-हार्वेस्ट)',
                        ),
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _isPreHarvest
                              ? const Color(0xFF7E22CE)
                              : const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3E8FF),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Pre-Booking Enabled',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF7E22CE),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.tr(
                          'Currently growing. Buyers can pre-book upcoming harvest at guaranteed price.',
                          'खेत में खड़ी फसल। खरीदार कटाई से पहले बुक कर सकते हैं।',
                        ),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        // Dynamic Sub-Panel for Pre-Harvest details
        if (_isPreHarvest) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFAF5FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD8B4FE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_month,
                      color: Color(0xFF9333EA),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.tr(
                        'Estimated Harvest Timeline & Maturity',
                        'अनुमानित कटाई समय एवं फसल अवस्था',
                      ),
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF581C87),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Quick Day Chips
                Text(
                  context.tr(
                    'In how many days will the crop be ready for harvest?',
                    'फसल कटाई के लिए कितने दिनों में तैयार होगी?',
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3B0764),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [7, 14, 21, 30, 45, 60].map((d) {
                    final isSel = _daysToHarvest == d;
                    return ChoiceChip(
                      label: Text('$d Days ($d दिन)'),
                      selected: isSel,
                      selectedColor: const Color(0xFF9333EA),
                      labelStyle: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: isSel ? Colors.white : const Color(0xFF581C87),
                      ),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: isSel
                              ? const Color(0xFF9333EA)
                              : const Color(0xFFE9D5FF),
                        ),
                      ),
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _daysToHarvest = d;
                            _daysToHarvestController.text = d.toString();
                            _estimatedHarvestDate = DateTime.now().add(
                              Duration(days: d),
                            );
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),

                // Manual days input & calculated estimated date
                Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: TextFormField(
                        controller: _daysToHarvestController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: context.tr('Custom Days', 'अन्य दिन'),
                          suffixText: 'd',
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFFD8B4FE),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFFD8B4FE),
                            ),
                          ),
                        ),
                        onChanged: (val) {
                          final parsed = int.tryParse(val.trim());
                          if (parsed != null && parsed > 0) {
                            setState(() {
                              _daysToHarvest = parsed;
                              _estimatedHarvestDate = DateTime.now().add(
                                Duration(days: parsed),
                              );
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE9D5FF)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.event_available,
                              color: Color(0xFF9333EA),
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Est. Harvest: ${_estimatedHarvestDate.day}/${_estimatedHarvestDate.month}/${_estimatedHarvestDate.year}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF581C87),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                const Divider(height: 1, color: Color(0xFFE9D5FF)),
                const SizedBox(height: 12),

                // Current Growth Stage Selector
                Text(
                  context.tr(
                    'Current Crop Growth Stage (फसल की वर्तमान अवस्था):',
                    'फसल की वर्तमान अवस्था:',
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3B0764),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children:
                      [
                        '🌱 Vegetative Stage',
                        '🌸 Flowering Stage',
                        '🌾 Grain Filling / Pod',
                        '☀️ Maturing / Near Harvest',
                      ].map((stage) {
                        final isSel = _cropGrowthStage == stage;
                        return ChoiceChip(
                          label: Text(stage),
                          selected: isSel,
                          selectedColor: const Color(0xFF7E22CE),
                          labelStyle: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSel
                                ? Colors.white
                                : const Color(0xFF4C1D95),
                          ),
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isSel
                                  ? const Color(0xFF7E22CE)
                                  : const Color(0xFFE9D5FF),
                            ),
                          ),
                          onSelected: (val) {
                            if (val) setState(() => _cropGrowthStage = stage);
                          },
                        );
                      }).toList(),
                ),

                const SizedBox(height: 14),
                // Pre-Booking Escrow Benefit Note
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E8FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.security,
                        size: 16,
                        color: Color(0xFF7E22CE),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.tr(
                            'Smart Escrow Assurance: When buyers pre-book, payments are securely locked in Polygon Smart Escrow. Funds are protected and released directly to your bank account upon post-harvest delivery.',
                            'स्मार्ट एस्क्रो गारंटी: जब खरीदार प्री-बुक करते हैं, तो भुगतान पॉलीगॉन स्मार्ट एस्क्रो में सुरक्षित लॉक हो जाता है। कटाई व डिलीवरी पर राशि सीधे आपके खाते में जारी होती है।',
                          ),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF581C87),
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
