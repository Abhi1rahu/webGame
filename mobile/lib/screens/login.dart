import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class LoginScreen extends StatefulWidget {
  final String backendUrl;

  const LoginScreen({
    Key? key,
    this.backendUrl = 'http://your-backend-url.com',
  }) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToOtpScreen() {
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _goToVerificationScreen() {
    _pageController.animateToPage(
      2,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _goBackToPhoneInput() {
    _pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
        elevation: 0,
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (index) {
          setState(() {
            _currentPage = index;
          });
        },
        children: [
          PhoneInputScreen(
            backendUrl: widget.backendUrl,
            onNext: _goToOtpScreen,
          ),
          OtpSendScreen(
            backendUrl: widget.backendUrl,
            onNext: _goToVerificationScreen,
            onBack: _goBackToPhoneInput,
          ),
          OtpVerificationScreen(
            backendUrl: widget.backendUrl,
            onVerificationSuccess: _handleVerificationSuccess,
            onBack: _goBackToPhoneInput,
          ),
        ],
      ),
    );
  }

  void _handleVerificationSuccess(String token) {
    // Handle successful verification
    // You can save the token, navigate to home, etc.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Login successful!')),
    );
    Navigator.of(context).pop();
  }
}

// ============================================================================
// PHONE INPUT SCREEN
// ============================================================================

class PhoneInputScreen extends StatefulWidget {
  final String backendUrl;
  final VoidCallback onNext;

  const PhoneInputScreen({
    Key? key,
    required this.backendUrl,
    required this.onNext,
  }) : super(key: key);

  @override
  State<PhoneInputScreen> createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends State<PhoneInputScreen> {
  late TextEditingController _phoneController;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  bool _validatePhoneNumber(String phone) {
    // Remove any non-digit characters
    String cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');
    // Check if it's a valid phone number (10-12 digits)
    return cleaned.length >= 10 && cleaned.length <= 12;
  }

  Future<void> _handleContinue() async {
    setState(() {
      _errorMessage = null;
    });

    if (_phoneController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a phone number';
      });
      return;
    }

    if (!_validatePhoneNumber(_phoneController.text)) {
      setState(() {
        _errorMessage = 'Please enter a valid phone number';
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Store phone number in a way accessible to next screens
      // You might want to use provider, riverpod, or pass via constructor
      widget.onNext();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 40),
          // Header
          const Text(
            'Enter Your Phone Number',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'We\'ll send you an OTP to verify your number',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 40),
          // Phone Input Field
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            enabled: !_isLoading,
            decoration: InputDecoration(
              hintText: '+1 (555) 123-4567',
              labelText: 'Phone Number',
              prefixIcon: const Icon(Icons.phone),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              errorText: _errorMessage,
              errorMaxLines: 2,
            ),
            onChanged: (value) {
              setState(() {
                _errorMessage = null;
              });
            },
          ),
          const SizedBox(height: 24),
          // Continue Button
          ElevatedButton(
            onPressed: _isLoading ? null : _handleContinue,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Continue',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
          const SizedBox(height: 16),
          // Info Text
          Center(
            child: Text(
              'Your phone number will be used to verify your account',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// OTP SEND SCREEN
// ============================================================================

class OtpSendScreen extends StatefulWidget {
  final String backendUrl;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const OtpSendScreen({
    Key? key,
    required this.backendUrl,
    required this.onNext,
    required this.onBack,
  }) : super(key: key);

  @override
  State<OtpSendScreen> createState() => _OtpSendScreenState();
}

class _OtpSendScreenState extends State<OtpSendScreen> {
  bool _isLoading = false;
  bool _otpSent = false;
  int _resendCountdown = 0;
  late Timer _countdownTimer;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _sendOtp();
  }

  @override
  void dispose() {
    if (_countdownTimer.isActive) {
      _countdownTimer.cancel();
    }
    super.dispose();
  }

  Future<void> _sendOtp() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${widget.backendUrl}/api/auth/send-otp'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'phoneNumber': '+1234567890', // Replace with actual phone number
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('Request timed out'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _otpSent = true;
          _successMessage = data['message'] ?? 'OTP sent successfully!';
          _resendCountdown = 60;
          _isLoading = false;
        });
        _startCountdown();
      } else {
        final data = jsonDecode(response.body);
        setState(() {
          _errorMessage =
              data['error'] ?? 'Failed to send OTP. Please try again.';
          _isLoading = false;
        });
      }
    } on TimeoutException {
      setState(() {
        _errorMessage = 'Request timed out. Please check your connection.';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error sending OTP: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _resendCountdown--;
      });
      if (_resendCountdown == 0) {
        timer.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 40),
          // Header
          const Text(
            'OTP Sent',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'An OTP has been sent to your phone number',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 40),
          // Status Icon
          if (_otpSent)
            Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Icon(
                  Icons.check_circle,
                  size: 60,
                  color: Colors.green[700],
                ),
              ),
            ),
          const SizedBox(height: 24),
          // Success Message
          if (_successMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                border: Border.all(color: Colors.green[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _successMessage!,
                style: TextStyle(
                  color: Colors.green[700],
                  fontSize: 14,
                ),
              ),
            ),
          // Error Message
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                border: Border.all(color: Colors.red[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _errorMessage!,
                style: TextStyle(
                  color: Colors.red[700],
                  fontSize: 14,
                ),
              ),
            ),
          const SizedBox(height: 32),
          // Proceed Button
          ElevatedButton(
            onPressed: _otpSent && !_isLoading
                ? () {
                    widget.onNext();
                  }
                : null,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Enter OTP',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 16),
          // Resend Button
          if (_resendCountdown > 0)
            Center(
              child: Text(
                'Resend OTP in ${_resendCountdown}s',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            )
          else if (_otpSent)
            TextButton(
              onPressed: _isLoading ? null : _sendOtp,
              child: const Text('Resend OTP'),
            ),
          const SizedBox(height: 16),
          // Back Button
          OutlinedButton.icon(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Change Phone Number'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// OTP VERIFICATION SCREEN
// ============================================================================

class OtpVerificationScreen extends StatefulWidget {
  final String backendUrl;
  final Function(String) onVerificationSuccess;
  final VoidCallback onBack;

  const OtpVerificationScreen({
    Key? key,
    required this.backendUrl,
    required this.onVerificationSuccess,
    required this.onBack,
  }) : super(key: key);

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  late List<TextEditingController> _otpControllers;
  bool _isLoading = false;
  String? _errorMessage;
  int _otpLength = 6;

  @override
  void initState() {
    super.initState();
    _otpControllers = List.generate(
      _otpLength,
      (index) => TextEditingController(),
    );
  }

  @override
  void dispose() {
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  String _getOtpValue() {
    return _otpControllers.map((c) => c.text).join();
  }

  bool _validateOtp() {
    String otp = _getOtpValue();
    return otp.length == _otpLength && otp.every((char) => char.isDigit);
  }

  Future<void> _verifyOtp() async {
    if (!_validateOtp()) {
      setState(() {
        _errorMessage = 'Please enter a valid OTP';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${widget.backendUrl}/api/auth/verify-otp'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'phoneNumber': '+1234567890', // Replace with actual phone number
          'otp': _getOtpValue(),
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('Request timed out'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token'] ?? data['accessToken'] ?? '';
        widget.onVerificationSuccess(token);
      } else if (response.statusCode == 400) {
        final data = jsonDecode(response.body);
        setState(() {
          _errorMessage = data['error'] ?? 'Invalid OTP. Please try again.';
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage =
              'Verification failed. Please try again or request a new OTP.';
          _isLoading = false;
        });
      }
    } on TimeoutException {
      setState(() {
        _errorMessage = 'Request timed out. Please check your connection.';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error verifying OTP: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 40),
          // Header
          const Text(
            'Verify OTP',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Enter the 6-digit OTP sent to your phone',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 40),
          // OTP Input Fields
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(
              _otpLength,
              (index) => OtpInputField(
                controller: _otpControllers[index],
                onChanged: (value) {
                  if (value.isNotEmpty && index < _otpLength - 1) {
                    FocusScope.of(context).nextFocus();
                  }
                  setState(() {
                    _errorMessage = null;
                  });
                },
                onBackspace: (value) {
                  if (value.isEmpty && index > 0) {
                    FocusScope.of(context).previousFocus();
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Error Message
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                border: Border.all(color: Colors.red[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _errorMessage!,
                style: TextStyle(
                  color: Colors.red[700],
                  fontSize: 14,
                ),
              ),
            ),
          const SizedBox(height: 32),
          // Verify Button
          ElevatedButton(
            onPressed: _isLoading ? null : _verifyOtp,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Verify OTP',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
          const SizedBox(height: 16),
          // Back Button
          OutlinedButton.icon(
            onPressed: !_isLoading ? widget.onBack : null,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// OTP INPUT FIELD WIDGET
// ============================================================================

class OtpInputField extends StatelessWidget {
  final TextEditingController controller;
  final Function(String) onChanged;
  final Function(String) onBackspace;

  const OtpInputField({
    Key? key,
    required this.controller,
    required this.onChanged,
    required this.onBackspace,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      height: 60,
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        decoration: InputDecoration(
          counterText: '',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.grey),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.blue, width: 2),
          ),
        ),
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
        onChanged: (value) {
          if (value.isEmpty) {
            onBackspace(value);
          } else {
            onChanged(value);
          }
        },
        onTap: () {
          controller.clear();
        },
      ),
    );
  }
}
