import 'package:flutter/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RodinEssentialBootstrap());
}

class RodinEssentialBootstrap extends StatefulWidget {
  const RodinEssentialBootstrap({super.key});

  @override
  State<RodinEssentialBootstrap> createState() => _RodinEssentialBootstrapState();
}

class _RodinEssentialBootstrapState extends State<RodinEssentialBootstrap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF090B10),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = Curves.easeInOutCubic.transform(_controller.value);
              return Transform.scale(
                scale: 0.985 + (t * 0.015),
                child: Opacity(
                  opacity: 0.82 + (t * 0.18),
                  child: child,
                ),
              );
            },
            child: const _ProofCard(),
          ),
        ),
      ),
    );
  }
}

class _ProofCard extends StatelessWidget {
  const _ProofCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 310,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
      decoration: BoxDecoration(
        color: const Color(0xFF151820),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: const Color(0x26FFFFFF),
          width: 1,
        ),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rodin Essential',
            style: TextStyle(
              color: Color(0xFFF7F7FA),
              fontSize: 27,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.7,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Flutter AOT • Rust host • Zero DEX',
            style: TextStyle(
              color: Color(0xFFAAAEB9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
