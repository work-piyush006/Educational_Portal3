// main.dart
// Educational Portal - Single-file Flutter app (User + Admin, offline PDFs, admin CRUD, reviews, quotes)
// Note: add dependencies in pubspec.yaml as mentioned in comments below and place assets accordingly.

// ----------------- Imports -----------------
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:url_launcher/url_launcher.dart';

// ✅ Global Error Handler
void setupErrorHandler() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    // App crash hone ki jagah safe logging
    Zone.current.handleUncaughtError(details.exception, details.stack!);
  };

  // Catch async errors
  runZonedGuarded(() {
    runApp(MyApp());
  }, (error, stackTrace) {
    debugPrint('⚠️ Caught Error: $error');
    debugPrintStack(stackTrace: stackTrace);
  });
}

// ✅ Entry Point
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setupErrorHandler(); // <-- yaha call karna hi padega
}

// ----------------- MyApp -----------------
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Educational Portal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
      ),
      home: SplashScreen(),
    );
  }
}

// ----------------- Splash Screen -----------------
class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}
class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen()),
      );
    });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Colors.white,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Replace with your asset logo; ensure assets/logo.png exists and is declared in pubspec.yaml
              Image.asset('assets/logo.png', height: 120, errorBuilder: (_, __, ___) => Icon(Icons.school, size: 100, color: Colors.deepPurple)),
              SizedBox(height: 20),
              Text(
                "Educational Portal",
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple),
              ),
              SizedBox(height: 10),
              Text("Made with ❤️ by Kulbhushan Jadeja",
                  style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------- HomeScreen -----------------
class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static List<Widget> _pages = <Widget>[
    UserDashboard(),
    ContactPage(),
    WebsitePage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  // Show admin login popup dialog (inline) triggered by settings icon
  void _showAdminLoginDialog() {
    showDialog(
      context: context,
      builder: (_) {
        final _user = TextEditingController();
        final _pass = TextEditingController();
        String error = '';
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: Text('Enter Admin Username & Password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: _user, decoration: InputDecoration(labelText: 'Username')),
                TextField(controller: _pass, decoration: InputDecoration(labelText: 'Password'), obscureText: true),
                if (error.isNotEmpty) SizedBox(height: 8),
                if (error.isNotEmpty) Text(error, style: TextStyle(color: Colors.red)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
              ElevatedButton(onPressed: () {
                final u = _user.text.trim();
                final p = _pass.text.trim();
                if (u == 'Piyush@2009' && p == '4209') {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => AdminDashboard()));
                } else {
                  setState(() {
                    // update local error inside dialog
                    // Can't call outer setState from here
                    error = 'Invalid Username or Password';
                  });
                }
              }, child: Text('Submit 🔘'))
            ],
          );
        });
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Educational Portal"),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: _showAdminLoginDialog,
          )
        ],
      ),
      body: _pages.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.phone), label: "Contact"),
          BottomNavigationBarItem(icon: Icon(Icons.web), label: "Website"),
        ],
      ),
      floatingActionButton: null,
    );
  }
}

// ------------------- BEGIN APP DATA & MODELS -------------------

// Helper model for PDF items
class PdfItem {
  String id;
  String name;
  String path; // asset path or local file path
  String source; // 'asset' or 'local'
  String category; // 'class11' | 'class12' | 'dpp'

  PdfItem({
    required this.id,
    required this.name,
    required this.path,
    required this.source,
    required this.category,
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'path': path, 'source': source, 'category': category};

  static PdfItem fromJson(Map<String, dynamic> m) => PdfItem(
        id: m['id'],
        name: m['name'],
        path: m['path'],
        source: m['source'],
        category: m['category'],
      );
}

// Singleton AppData to manage local storage, bundled list, reviews, quotes, contact info
class AppData {
  AppData._privateConstructor();
  static final AppData instance = AppData._privateConstructor();

  late SharedPreferences prefs;
  late Directory appDocDir;
  late Directory pdfDir;

  // Bundled PDFs - update filenames to match your assets
  final List<PdfItem> bundled = [
    PdfItem(
        id: 'b_class11_cs',
        name: 'CS Notes - Class 11',
        path: 'assets/pdfs/class11/cs_notes.pdf',
        source: 'asset',
        category: 'class11'),
    PdfItem(
        id: 'b_class12_cs',
        name: 'CS Notes - Class 12',
        path: 'assets/pdfs/class12/cs_notes.pdf',
        source: 'asset',
        category: 'class12'),
    PdfItem(
        id: 'b_dpp_stack',
        name: 'Stack DPP',
        path: 'assets/pdfs/dpp/stack_dpp.pdf',
        source: 'asset',
        category: 'dpp'),
    // Add more bundled items matching files you add to assets
  ];

  // Local PDFs added by Admin at runtime (persisted in prefs)
  List<PdfItem> local = [];

  // Reviews stored locally
  List<Map<String, dynamic>> reviews = [];

  // Quotes
  List<String> quotes = [];

  // Contact & socials
  String contactNumber = '';
  List<String> socialHandles = [];

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    appDocDir = await getApplicationDocumentsDirectory();
    pdfDir = Directory('${appDocDir.path}/educational_portal_pdfs');
    if (!await pdfDir.exists()) await pdfDir.create(recursive: true);
    _loadLocalPdfs();
    _loadReviews();
    await _loadQuotes();
    _loadContacts();
  }

  // Local PDFs stored in prefs as JSON
  void _loadLocalPdfs() {
    final s = prefs.getString('local_pdfs') ?? '[]';
    final List lw = jsonDecode(s);
    local = lw.map((e) => PdfItem.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> _saveLocalPdfs() async {
    final s = jsonEncode(local.map((e) => e.toJson()).toList());
    await prefs.setString('local_pdfs', s);
  }

  // Reviews
  void _loadReviews() {
    final s = prefs.getString('reviews') ?? '[]';
    final List rw = jsonDecode(s);
    reviews = rw.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> addReview(double rating, String name, String comment) async {
    final r = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'rating': rating,
      'name': name.isEmpty ? 'Anonymous' : name,
      'comment': comment,
      'ts': DateTime.now().toIso8601String()
    };
    reviews.insert(0, r);
    await prefs.setString('reviews', jsonEncode(reviews));
  }

  Future<void> deleteReview(String id) async {
    reviews.removeWhere((r) => r['id'] == id);
    await prefs.setString('reviews', jsonEncode(reviews));
  }

  // Quotes
  Future<void> _loadQuotes() async {
    final s = prefs.getString('quotes');
    if (s != null) {
      final List qw = jsonDecode(s);
      quotes = qw.map((e) => e.toString()).toList();
    } else {
      // Attempt to load bundled quotes from assets file if exists
      try {
        final raw = await rootBundle.loadString('assets/motivational_quotes.json');
        final List aq = jsonDecode(raw);
        quotes = aq.map((e) => e.toString()).toList();
      } catch (e) {
        // fallback quotes
        quotes = [
          "Believe in yourself.",
          "Consistency is the key to success.",
          "Small steps every day make big changes.",
          "Practice, don't memorize.",
          "Stay curious and keep learning."
        ];
      }
      await prefs.setString('quotes', jsonEncode(quotes));
    }
  }

  Future<void> addQuote(String q) async {
    quotes.insert(0, q);
    await prefs.setString('quotes', jsonEncode(quotes));
  }

  Future<void> deleteQuoteAt(int idx) async {
    if (idx >= 0 && idx < quotes.length) {
      quotes.removeAt(idx);
      await prefs.setString('quotes', jsonEncode(quotes));
    }
  }

  // Contacts
  void _loadContacts() {
    contactNumber = prefs.getString('contact_number') ?? '';
    final s = prefs.getString('social_handles') ?? '[]';
    final List sw = jsonDecode(s);
    socialHandles = sw.map((e) => e.toString()).toList();
  }

  Future<void> updateContact(String number, List<String> socials) async {
    contactNumber = number;
    socialHandles = socials;
    await prefs.setString('contact_number', contactNumber);
    await prefs.setString('social_handles', jsonEncode(socialHandles));
  }

  // Get merged list of PDFs for a category (bundled + local)
  List<PdfItem> getPdfs(String category) {
    final b = bundled.where((p) => p.category == category).toList();
    final l = local.where((p) => p.category == category).toList();
    return [...b, ...l];
  }

  // Add PDF from admin (sourceFile path from file picker)
  Future<void> addLocalPdfFromPath(String sourcePath, String name, String category) async {
    final src = File(sourcePath);
    if (!await src.exists()) throw Exception('Source file not found');
    final filename = '${DateTime.now().millisecondsSinceEpoch}_${src.uri.pathSegments.last}';
    final dest = File('${pdfDir.path}/$filename');
    await src.copy(dest.path);
    final item = PdfItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        path: dest.path,
        source: 'local',
        category: category);
    local.insert(0, item);
    await _saveLocalPdfs();
  }

  // Delete a local pdf (removes file & metadata)
  Future<void> deleteLocalPdf(String id) async {
    final found = local.firstWhere((p) => p.id == id, orElse: () => throw Exception('Not found'));
    try {
      final f = File(found.path);
      if (await f.exists()) await f.delete();
    } catch (e) {
      // ignore
    }
    local.removeWhere((p) => p.id == id);
    await _saveLocalPdfs();
  }

  // Rename local pdf
  Future<void> renameLocalPdf(String id, String newName) async {
    final idx = local.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      local[idx].name = newName;
      await _saveLocalPdfs();
    }
  }

  // Helper to copy asset PDF to a temp file for viewing
  Future<String> copyAssetToFile(String assetPath) async {
    final bytes = await rootBundle.load(assetPath);
    final buffer = bytes.buffer;
    final outFile = File('${appDocDir.path}/temp_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await outFile.writeAsBytes(buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
    return outFile.path;
  }
}

// ------------------- User Dashboard -------------------
class UserDashboard extends StatefulWidget {
  @override
  _UserDashboardState createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    AppData.instance.init().then((_) {
      setState(() {
        loaded = true;
      });
    });
  }

  void _openReviewScreen() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewScreen()));
  }

  void _openClassSelection() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ClassSelectionScreen()));
  }

  Widget _quotesSlider() {
    final q = AppData.instance.quotes;
    if (q.isEmpty) return SizedBox.shrink();
    return CarouselSlider(
      options: CarouselOptions(height: 80, autoPlay: true, enlargeCenterPage: true),
      items: q.map((text) {
        return Container(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Center(child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontStyle: FontStyle.italic))));
      }).toList(),
    );
  }

  Widget _reviewPreview() {
    final r = AppData.instance.reviews;
    if (r.isEmpty) {
      return Column(
        children: [
          Text('Be the first to review us 👇', style: TextStyle(fontSize: 16)),
          SizedBox(height: 8),
          ElevatedButton(onPressed: _openReviewScreen, child: Text('Review our App 🔘'))
        ],
      );
    } else {
      return Column(
        children: [
          Text('User Reviews', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Container(
            height: 140,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: r.length,
              itemBuilder: (context, idx) {
                final item = r[idx];
                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 8),
                  child: Container(
                    width: 260,
                    padding: EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item['name'] ?? 'Anonymous', style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 6),
                        RatingBarIndicator(
                          rating: (item['rating'] ?? 5).toDouble(),
                          itemBuilder: (context, _) => Icon(Icons.star, color: Colors.amber),
                          itemCount: 5,
                          itemSize: 18.0,
                        ),
                        SizedBox(height: 6),
                        Expanded(child: Text(item['comment'] ?? '', overflow: TextOverflow.fade)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: 8),
          ElevatedButton(onPressed: _openReviewScreen, child: Text('Write a Review'))
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Image.asset('assets/logo.png', height: 100, errorBuilder: (_, __, ___) => Icon(Icons.school, size: 80, color: Colors.deepPurple)),
          SizedBox(height: 12),
          Text('This app is made for class 11 & 12 Computer Science students to learn with our notes & practice with DPP.',
              textAlign: TextAlign.center),
          SizedBox(height: 16),
          _quotesSlider(),
          SizedBox(height: 16),
          _reviewPreview(),
          SizedBox(height: 20),
          ElevatedButton(onPressed: _openClassSelection, child: Text('Next 🔘')),
        ],
      ),
    );
  }
}

// ------------------- Class Selection Screen -------------------
class ClassSelectionScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Select Class / DPP'),
      ),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PdfListScreen(category: 'class11', title: 'Class 11'))),
              child: Text('11TH CLASS'),
            ),
            SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PdfListScreen(category: 'class12', title: 'Class 12'))),
              child: Text('12TH CLASS'),
            ),
            SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PdfListScreen(category: 'dpp', title: 'DPP'))),
              child: Text('DPP'),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------- Pdf List Screen -------------------
class PdfListScreen extends StatefulWidget {
  final String category;
  final String title;
  PdfListScreen({required this.category, required this.title});

  @override
  _PdfListScreenState createState() => _PdfListScreenState();
}

class _PdfListScreenState extends State<PdfListScreen> {
  List<PdfItem> items = [];

  @override
  void initState() {
    super.initState();
    items = AppData.instance.getPdfs(widget.category);
  }

  Future<void> refreshList() async {
    setState(() {
      items = AppData.instance.getPdfs(widget.category);
    });
  }

  void _openPdf(PdfItem p) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(item: p)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(icon: Icon(Icons.refresh), onPressed: refreshList),
        ],
      ),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, idx) {
          final p = items[idx];
          return ListTile(
            leading: Icon(Icons.picture_as_pdf),
            title: Text(p.name),
            subtitle: Text(p.source == 'asset' ? 'Bundled' : 'Downloaded'),
            trailing: p.source == 'local' ? TextButton(child: Text('Local'), onPressed: null) : null,
            onTap: () => _openPdf(p),
          );
        },
      ),
    );
  }
}

// ------------------- PDF Viewer Screen -------------------
class PdfViewerScreen extends StatefulWidget {
  final PdfItem item;
  const PdfViewerScreen({required this.item, super.key});

  @override
  _PdfViewerScreenState createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  String? filePath;
  bool loading = true;
  PdfController? _pdfController;

  @override
  void initState() {
    super.initState();
    _prepareFile();
  }

  Future<void> _prepareFile() async {
    try {
      if (widget.item.source == 'asset') {
        filePath = await AppData.instance.copyAssetToFile(widget.item.path);
      } else {
        filePath = widget.item.path;
      }

      _pdfController = PdfController(
        document: PdfDocument.openFile(filePath!),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error opening PDF')),
      );
      Navigator.pop(context);
      return;
    }
    setState(() {
      loading = false;
    });
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.item.name)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.item.name)),
      body: PdfView(
        controller: _pdfController!,
      ),
    );
  }
}
// ------------------- Review Screen -------------------
class ReviewScreen extends StatefulWidget {
  @override
  _ReviewScreenState createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  double rating = 5.0;
  final _nameCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();
  bool submitting = false;

  Future<void> _submit() async {
    if (submitting) return;
    setState(() => submitting = true);
    await AppData.instance.addReview(rating, _nameCtrl.text.trim(), _commentCtrl.text.trim());
    setState(() => submitting = false);
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              content: Text('Thanks for Rating us ☺️'),
              actions: [
                TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pop(context);
                    },
                    child: Text('OK'))
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Review App'),
      ),
      body: Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          children: [
            Text('Rate us', style: TextStyle(fontSize: 18)),
            SizedBox(height: 8),
            RatingBar.builder(
              initialRating: rating,
              minRating: 1,
              allowHalfRating: true,
              itemCount: 5,
              itemBuilder: (_, __) => Icon(Icons.star, color: Colors.amber),
              onRatingUpdate: (r) => rating = r,
            ),
            SizedBox(height: 12),
            TextField(controller: _nameCtrl, decoration: InputDecoration(labelText: 'Your Name (optional)')),
            SizedBox(height: 8),
            TextField(controller: _commentCtrl, decoration: InputDecoration(labelText: 'Write a review'), maxLines: 4),
            SizedBox(height: 12),
            ElevatedButton(onPressed: _submit, child: submitting ? CircularProgressIndicator(color: Colors.white) : Text('Submit Review 🔘'))
          ],
        ),
      ),
    );
  }
}

// ------------------- Admin Section -------------------
// Admin Dashboard (tabs: PDFs, Reviews, Quotes, Contact)
class AdminDashboard extends StatefulWidget {
  @override
  _AdminDashboardState createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int tabIndex = 0;

  @override
  void initState() {
    super.initState();
    AppData.instance.init();
  }

  Widget _tabContent() {
    switch (tabIndex) {
      case 0:
        return ManagePdfsTab(onChanged: () => setState(() {}));
      case 1:
        return ManageReviewsTab(onChanged: () => setState(() {}));
      case 2:
        return ManageQuotesTab(onChanged: () => setState(() {}));
      case 3:
        return UpdateContactTab(onChanged: () => setState(() {}));
      default:
        return Container();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Admin Dashboard'),
        actions: [
          IconButton(
              icon: Icon(Icons.logout),
              onPressed: () {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen()));
              })
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: Row(
              children: [
                Expanded(child: TextButton(onPressed: () => setState(() => tabIndex = 0), child: Text('PDFs'))),
                Expanded(child: TextButton(onPressed: () => setState(() => tabIndex = 1), child: Text('Reviews'))),
                Expanded(child: TextButton(onPressed: () => setState(() => tabIndex = 2), child: Text('Quotes'))),
                Expanded(child: TextButton(onPressed: () => setState(() => tabIndex = 3), child: Text('Contact'))),
              ],
            ),
          ),
          Expanded(child: _tabContent())
        ],
      ),
    );
  }
}

// ManagePdfsTab
class ManagePdfsTab extends StatefulWidget {
  final VoidCallback onChanged;
  ManagePdfsTab({required this.onChanged});
  @override
  _ManagePdfsTabState createState() => _ManagePdfsTabState();
}

class _ManagePdfsTabState extends State<ManagePdfsTab> {
  List<PdfItem> localPdfs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    localPdfs = AppData.instance.local;
    setState(() {});
  }

  Future<void> _pickAndAdd() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result == null) return;
    final path = result.files.single.path!;
    String name = result.files.single.name;
    String category = 'class11';
    await showDialog(
        context: context,
        builder: (_) {
          final nameCtrl = TextEditingController(text: name);
          String cat = 'class11';
          return AlertDialog(
            title: Text('Add PDF'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nameCtrl, decoration: InputDecoration(labelText: 'Display Name')),
              DropdownButtonFormField<String>(
                value: 'class11',
                items: [
                  DropdownMenuItem(child: Text('Class 11'), value: 'class11'),
                  DropdownMenuItem(child: Text('Class 12'), value: 'class12'),
                  DropdownMenuItem(child: Text('DPP'), value: 'dpp'),
                ],
                onChanged: (v) => cat = v ?? 'class11',
                decoration: InputDecoration(labelText: 'Category'),
              ),
            ]),
            actions: [
              TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    category = cat;
                    name = nameCtrl.text.trim();
                    if (name.isEmpty) name = result.files.single.name;
                    await AppData.instance.addLocalPdfFromPath(path, name, category);
                    _load();
                    widget.onChanged();
                  },
                  child: Text('Add'))
            ],
          );
        });
  }

  Future<void> _deletePdf(String id) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              content: Text('Delete this PDF?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Delete')),
              ],
            ));
    if (ok == true) {
      await AppData.instance.deleteLocalPdf(id);
      _load();
      widget.onChanged();
    }
  }

  Future<void> _renamePdf(String id) async {
    final current = AppData.instance.local.firstWhere((e) => e.id == id);
    final ctrl = TextEditingController(text: current.name);
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: Text('Rename PDF'),
              content: TextField(controller: ctrl, decoration: InputDecoration(labelText: 'New name')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Save')),
              ],
            ));
    if (ok == true) {
      await AppData.instance.renameLocalPdf(id, ctrl.text.trim());
      _load();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final locals = AppData.instance.local;
    return Padding(
      padding: EdgeInsets.all(12),
      child: Column(
        children: [
          ElevatedButton.icon(onPressed: _pickAndAdd, icon: Icon(Icons.add), label: Text('Add PDF')),
          SizedBox(height: 10),
          Expanded(
            child: locals.isEmpty
                ? Center(child: Text('No local PDFs uploaded yet.'))
                : ListView.builder(
                    itemCount: locals.length,
                    itemBuilder: (_, idx) {
                      final p = locals[idx];
                      return ListTile(
                        leading: Icon(Icons.picture_as_pdf),
                        title: Text(p.name),
                        subtitle: Text('Category: ${p.category}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(icon: Icon(Icons.edit), onPressed: () => _renamePdf(p.id)),
                          IconButton(icon: Icon(Icons.delete), onPressed: () => _deletePdf(p.id)),
                        ]),
                      );
                    },
                  ),
          )
        ],
      ),
    );
  }
# (file continues...)

// ------------------- Manage Reviews Tab -------------------
class ManageReviewsTab extends StatefulWidget {
  final VoidCallback onChanged;
  ManageReviewsTab({required this.onChanged});
  @override
  _ManageReviewsTabState createState() => _ManageReviewsTabState();
}

class _ManageReviewsTabState extends State<ManageReviewsTab> {
  void _delete(String id) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              content: Text('Delete this review?'),
              actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')), TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Delete'))],
            ));
    if (ok == true) {
      await AppData.instance.deleteReview(id);
      setState(() {});
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = AppData.instance.reviews;
    return r.isEmpty
        ? Center(child: Text('No reviews yet'))
        : ListView.builder(
            itemCount: r.length,
            itemBuilder: (_, idx) {
              final item = r[idx];
              return ListTile(
                title: Text(item['name'] ?? 'Anonymous'),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  RatingBarIndicator(rating: (item['rating'] ?? 5).toDouble(), itemBuilder: (_, __) => Icon(Icons.star, color: Colors.amber), itemCount: 5, itemSize: 16.0),
                  SizedBox(height: 4),
                  Text(item['comment'] ?? ''),
                ]),
                trailing: IconButton(icon: Icon(Icons.delete), onPressed: () => _delete(item['id'])),
              );
            },
          );
  }
}

// ------------------- Manage Quotes Tab -------------------
class ManageQuotesTab extends StatefulWidget {
  final VoidCallback onChanged;
  ManageQuotesTab({required this.onChanged});
  @override
  _ManageQuotesTabState createState() => _ManageQuotesTabState();
}

class _ManageQuotesTabState extends State<ManageQuotesTab> {
  final _ctrl = TextEditingController();

  Future<void> _addQuote() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    await AppData.instance.addQuote(text);
    _ctrl.clear();
    setState(() {});
    widget.onChanged();
  }

  Future<void> _deleteAt(int idx) async {
    await AppData.instance.deleteQuoteAt(idx);
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final qs = AppData.instance.quotes;
    return Padding(
      padding: EdgeInsets.all(12),
      child: Column(
        children: [
          Row(children: [
            Expanded(child: TextField(controller: _ctrl, decoration: InputDecoration(hintText: 'New motivational quote'))),
            SizedBox(width: 8),
            ElevatedButton(onPressed: _addQuote, child: Text('Add'))
          ]),
          SizedBox(height: 10),
          Expanded(
            child: qs.isEmpty
                ? Center(child: Text('No quotes yet'))
                : ListView.builder(
                    itemCount: qs.length,
                    itemBuilder: (_, idx) => ListTile(
                      title: Text(qs[idx]),
                      trailing: IconButton(icon: Icon(Icons.delete), onPressed: () => _deleteAt(idx)),
                    )),
          )
        ],
      ),
    );
  }
}

// ------------------- Update Contact Tab -------------------
class UpdateContactTab extends StatefulWidget {
  final VoidCallback onChanged;
  UpdateContactTab({required this.onChanged});
  @override
  _UpdateContactTabState createState() => _UpdateContactTabState();
}

class _UpdateContactTabState extends State<UpdateContactTab> {
  final _phone = TextEditingController();
  final _social = TextEditingController();

  @override
  void initState() {
    super.initState();
    _phone.text = AppData.instance.contactNumber;
    _social.text = AppData.instance.socialHandles.join(', ');
  }

  Future<void> _save() async {
    final phone = _phone.text.trim();
    final socials = _social.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    await AppData.instance.updateContact(phone, socials);
    widget.onChanged();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Contact updated')));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(12),
      child: Column(children: [
        TextField(controller: _phone, decoration: InputDecoration(labelText: 'Contact Number')),
        TextField(controller: _social, decoration: InputDecoration(labelText: 'Social Handles (comma separated)')),
        SizedBox(height: 10),
        ElevatedButton(onPressed: _save, child: Text('Save')),
      ]),
    );
  }
}

// ------------------- Website Page -------------------
class WebsitePage extends StatelessWidget {
  final String website = 'https://kulbhushan.freevar.com';

  void _open() async {
    final uri = Uri.parse(website);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton.icon(
        onPressed: _open,
        icon: Icon(Icons.language),
        label: Text('Open website'),
      ),
    );
  }
}

// ------------------- Contact Page -------------------
class ContactPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = AppData.instance.contactNumber;
    final socials = AppData.instance.socialHandles;
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Text(c.isNotEmpty ? 'Contact No.: $c' : 'Contact no. set by admin soon'),
          SizedBox(height: 10),
          if (socials.isEmpty)
            Text('Social media handles not set yet')
          else
            ...socials.map((s) => Text(s)).toList(),
        ],
      ),
    );
  }
}

// ------------------- End of main.dart -------------------
/*
  Setup notes:
  1) Add these dependencies to pubspec.yaml:
    path_provider, shared_preferences, file_picker, flutter_rating_bar, carousel_slider, flutter_pdfview, url_launcher

  2) Add assets in pubspec.yaml:
    assets:
      - assets/logo.png
      - assets/motivational_quotes.json
      - assets/pdfs/class11/cs_notes.pdf
      - assets/pdfs/class12/cs_notes.pdf
      - assets/pdfs/dpp/stack_dpp.pdf
      ... add your pdfs

  3) To build:
    flutter pub get
    flutter build apk --release

  4) For Play Store signing, generate a keystore and sign the app as per Flutter docs.
*/
