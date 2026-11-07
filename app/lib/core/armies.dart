/// The 8 launch armies (docs/GAME_RULES.md §2). Ids match the server's `Army` values.
class ArmyInfo {
  const ArmyInfo(this.id, this.name, this.perk, this.ability, this.abilityName, {this.abilityNeedsTerritory = false});
  final String id;
  final String name;
  final String perk;
  final String ability;
  final String abilityName;
  final bool abilityNeedsTerritory;

  String get commander => 'assets/armies/commanders/$id.png';
  String get fort => 'assets/armies/forts/$id.png';
  String get soldier => 'assets/armies/soldiers/$id.png';
  String get abilityIcon => 'assets/ui/abilities/$id.webp';
}

const armies = <ArmyInfo>[
  ArmyInfo('islamic', 'الفتوحات الإسلامية', '+50 نقطة على كل احتلال', 'اختيار أرض إضافية بجولة توسّع وحدة', 'فتح'),
  ArmyInfo('ayyubid', 'الأيوبيون', 'قاعدتك بتبلّش بقيمة 1100', 'أول ضربة ناجحة على قاعدتك ما بتوقّع برج', 'صمود'),
  ArmyInfo('crusader', 'الصليبيون', 'الدفاع الناجح بيعطي +150', 'ضربتك الجاية على قاعدة بتوقّع برجين', 'حصار'),
  ArmyInfo(
    'roman',
    'الرومان',
    '+25 لكل أراضيك ببداية المعارك',
    'بتربح التعادل الجاي كمدافع بلا سؤال حسم',
    'تشكيل السلحفاة',
  ),
  ArmyInfo(
    'pharaoh',
    'الفراعنة',
    '+2 ثانية بالأسئلة الرقمية',
    '+300 لقيمة أرض من أراضيك',
    'الهرم',
    abilityNeedsTerritory: true,
  ),
  ArmyInfo('mongol', 'المغول', 'وقتك أسرع 0.2 ث وقت تهاجم', 'بعد هجوم ناجح بتهاجم مرة تانية فوراً', 'اجتياح'),
  ArmyInfo('ottoman', 'العثمانيون', 'الاحتلال بيعطي +150', 'بتربح التعادل الجاي كمهاجم بلا سؤال حسم', 'الإنكشارية'),
  ArmyInfo(
    'ww2',
    'الحرب العالمية الثانية',
    'أول أرض بتختارها ممكن تكون أي أرض فاضية',
    'هاجم أي أرض للعدو حتى لو مش جنبك',
    'إنزال جوي',
  ),
];

ArmyInfo armyOf(String? id) => armies.firstWhere((a) => a.id == id, orElse: () => armies.first);

const islamicArmies = {'islamic', 'ayyubid', 'ottoman'};

/// Power-ups (docs/GAME_RULES.md §5).
const powerupNames = {'remove_two': 'حذف جوابين', 'hint': 'تلميح', 'shield': 'درع', 'double': 'مضاعفة'};
