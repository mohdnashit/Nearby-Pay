import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const NearbyPayApp());
}

class NearbyPayApp extends StatelessWidget {
  const NearbyPayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nearby Pay',
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
    );
  }
}

/// simple random user id for this demo
String generateUserID() {
  final random = Random();
  return "user_${random.nextInt(999999)}";
}

/// HOME: PAY / RECEIVE / MERCHANT RECEIVE
class HomeScreen extends StatefulWidget {
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? myID;

  /// normal PAY – broadcast yourself as non-merchant
  Future<void> onPay() async {
    myID = generateUserID();

    await FirebaseFirestore.instance.collection("broadcast").doc(myID).set({
      "user_id": myID,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      "isMerchant": false,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Broadcasting your ID: $myID")),
    );
  }

  void onReceive() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ReceiveScreen(isMerchant: false),
      ),
    );
  }

  void onMerchantReceive() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ReceiveScreen(isMerchant: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Nearby Pay"),
        centerTitle: true,
        backgroundColor: Colors.blue,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // PAY
            ElevatedButton(
              onPressed: onPay,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding:
                    const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
              ),
              child: const Text("PAY", style: TextStyle(fontSize: 20)),
            ),
            const SizedBox(height: 25),

            // NORMAL RECEIVE
            ElevatedButton(
              onPressed: onReceive,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding:
                    const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
              ),
              child: const Text("RECEIVE", style: TextStyle(fontSize: 20)),
            ),
            const SizedBox(height: 25),

            // MERCHANT RECEIVE
            ElevatedButton(
              onPressed: onMerchantReceive,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
              ),
              child:
                  const Text("MERCHANT RECEIVE", style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }
}

/// RECEIVE SCREEN – does "scanning", merchant priority, cleanup
class ReceiveScreen extends StatefulWidget {
  final bool isMerchant;
  const ReceiveScreen({super.key, required this.isMerchant});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    // if merchant, broadcast a merchant signal once
    if (widget.isMerchant) {
      final merchantID = "merchant_${DateTime.now().millisecondsSinceEpoch}";
      FirebaseFirestore.instance.collection("broadcast").doc(merchantID).set({
        "user_id": merchantID,
        "timestamp": DateTime.now().millisecondsSinceEpoch,
        "isMerchant": true,
      });
    }

    // "scanning" – refresh & clean every 2 seconds
    _timer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted) return;
      setState(() {});
      await _cleanOldBroadcasts();
    });
  }

  Future<void> _cleanOldBroadcasts() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - 20000; // older than 20s

    final oldDocs = await FirebaseFirestore.instance
        .collection("broadcast")
        .where("timestamp", isLessThan: cutoff)
        .get();

    for (var d in oldDocs.docs) {
      await d.reference.delete();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.isMerchant ? "Merchant Mode (Scanning)" : "Nearby Users"),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          // scanning bar
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.wifi_tethering, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                "Scanning for nearby users...",
                style: TextStyle(fontSize: 16, color: Colors.blue),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),

          // list of nearby users
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("broadcast")
                  .orderBy("timestamp", descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;

                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      "No nearby users right now.\nAsk someone to press PAY.",
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                // merchants first
                final merchants = docs
                    .where((d) =>
                        (d.data() as Map<String, dynamic>)['isMerchant'] ==
                        true)
                    .toList();

                final normalUsers = docs
                    .where((d) =>
                        (d.data() as Map<String, dynamic>)['isMerchant'] ==
                            false ||
                        (d.data() as Map<String, dynamic>)['isMerchant'] ==
                            null)
                    .toList();

                final sorted = [...merchants, ...normalUsers];

                return ListView(
                  children: sorted.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final bool merchant = data['isMerchant'] == true;
                    final String userId = data['user_id'] ?? 'unknown';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            merchant ? Colors.blueAccent : Colors.grey,
                        child: Icon(
                          merchant ? Icons.store : Icons.person,
                          color: Colors.white,
                        ),
                      ),
                      title: Text(
                        merchant ? "MERCHANT: $userId" : "User: $userId",
                      ),
                      subtitle: Text(merchant
                          ? "Priority Merchant"
                          : "Ready to receive payment"),
                      trailing: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PayToUserScreen(targetUser: userId),
                            ),
                          );
                        },
                        child: const Text("PAY"),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// PAYMENT SCREEN
class PayToUserScreen extends StatelessWidget {
  final String targetUser;

  PayToUserScreen({super.key, required this.targetUser});

  final TextEditingController amountController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Send Payment"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              "Pay to: $targetUser",
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Enter Amount",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                if (amountController.text.trim().isEmpty) return;

                await FirebaseFirestore.instance
                    .collection("transactions")
                    .add({
                  "to": targetUser,
                  "amount": amountController.text.trim(),
                  "timestamp": DateTime.now().millisecondsSinceEpoch,
                });

                if (!context.mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Payment Sent!")),
                );

                Navigator.pop(context);
              },
              child: const Text("Send Payment"),
            ),
          ],
        ),
      ),
    );
  }
}
