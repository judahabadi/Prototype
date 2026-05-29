#!/usr/bin/env python3
"""
Generate seed translation JSON files for the Prototype keyboard.

This produces ~150 high-confidence common-word translations per pair
across all 12 languages (132 directional pairs total — we ship 24 of
the most useful, matching the spec).

The files this writes are SEEDS. For App Store submission you should
expand each to 3k–10k entries from a real source (Wiktionary CC0 dumps,
OPUS, Tatoeba). The runtime always falls back to MyMemory for misses,
so the keyboard is fully functional with the seed.
"""
import json
import os
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "PrototypeKeyboard" / "Resources"
OUT.mkdir(parents=True, exist_ok=True)

# English source: ~150 most common nouns, verbs, adjectives, function words.
# Each row: en, es, fr, de, pt, ru, hi, bn, ar, he, zh (pinyin), ja (romaji)
ROWS = [
    # function words / pronouns
    ("the", "el", "le", "der", "o", "э́тот", "वह", "সেই", "ال", "ה", "zhege", "kono"),
    ("a",   "un", "un", "ein", "um", "оди́н", "एक", "এক", "واحد", "אחד", "yi", "ichi"),
    ("and", "y", "et", "und", "e", "и", "और", "এবং", "و", "ו", "he", "to"),
    ("or",  "o", "ou", "oder", "ou", "или", "या", "অথবা", "أو", "או", "huozhe", "matawa"),
    ("not", "no", "ne", "nicht", "não", "не", "नहीं", "না", "لا", "לא", "bu", "nai"),
    ("yes", "sí", "oui", "ja", "sim", "да", "हाँ", "হ্যাঁ", "نعم", "כן", "shi", "hai"),
    ("no",  "no", "non", "nein", "não", "нет", "नहीं", "না", "لا", "לא", "bu", "iie"),
    ("i",   "yo", "je", "ich", "eu", "я", "मैं", "আমি", "أنا", "אני", "wo", "watashi"),
    ("you", "tú", "tu", "du", "você", "ты", "तुम", "তুমি", "أنت", "אתה", "ni", "anata"),
    ("he",  "él", "il", "er", "ele", "он", "वह", "সে", "هو", "הוא", "ta", "kare"),
    ("she", "ella", "elle", "sie", "ela", "она", "वह", "সে", "هي", "היא", "ta", "kanojo"),
    ("we",  "nosotros", "nous", "wir", "nós", "мы", "हम", "আমরা", "نحن", "אנחנו", "women", "watashitachi"),
    ("they","ellos", "ils", "sie", "eles", "они", "वे", "তারা", "هم", "הם", "tamen", "karera"),
    ("this","este", "ce", "dies", "este", "э́то", "यह", "এই", "هذا", "זה", "zhege", "kore"),
    ("that","ese", "cela", "das", "esse", "то", "वह", "ওই", "ذلك", "ההוא", "nage", "are"),
    ("here","aquí", "ici", "hier", "aqui", "здесь", "यहाँ", "এখানে", "هنا", "כאן", "zheli", "koko"),
    ("there","allí", "là", "dort", "ali", "там", "वहाँ", "সেখানে", "هناك", "שם", "nali", "asoko"),
    ("what","qué", "quoi", "was", "o que", "что", "क्या", "কী", "ماذا", "מה", "shenme", "nani"),
    ("who", "quién", "qui", "wer", "quem", "кто", "कौन", "কে", "من", "מי", "shei", "dare"),
    ("when","cuándo", "quand", "wann", "quando", "когда", "कब", "কখন", "متى", "מתי", "shenme shihou", "itsu"),
    ("where","dónde", "où", "wo", "onde", "где", "कहाँ", "কোথায়", "أين", "איפה", "nali", "doko"),
    ("why", "por qué", "pourquoi", "warum", "por que", "почему", "क्यों", "কেন", "لماذا", "למה", "weishenme", "naze"),
    ("how", "cómo", "comment", "wie", "como", "как", "कैसे", "কেমন", "كيف", "איך", "zenme", "dou"),
    ("all", "todo", "tout", "alle", "todo", "всё", "सब", "সব", "كل", "כל", "suoyou", "subete"),
    ("some","alguno", "quelque", "einige", "algum", "не́сколько", "कुछ", "কিছু", "بعض", "כמה", "yixie", "ikutsuka"),
    ("with","con", "avec", "mit", "com", "с", "के साथ", "সঙ্গে", "مع", "עם", "he", "to"),
    ("for", "para", "pour", "für", "para", "для", "के लिए", "জন্য", "لـ", "עבור", "weile", "no tame"),
    ("from","de", "de", "von", "de", "от", "से", "থেকে", "من", "מ", "cong", "kara"),
    ("to",  "a", "à", "zu", "para", "к", "को", "প্রতি", "إلى", "אל", "dao", "e"),
    ("in",  "en", "dans", "in", "em", "в", "में", "মধ্যে", "في", "ב", "zai", "naka"),
    ("on",  "en", "sur", "auf", "em", "на", "पर", "উপর", "على", "על", "zai", "ue"),
    ("at",  "en", "à", "an", "em", "в", "पर", "এ", "في", "ב", "zai", "de"),
    ("of",  "de", "de", "von", "de", "из", "का", "এর", "من", "של", "de", "no"),
    ("but", "pero", "mais", "aber", "mas", "но", "लेकिन", "কিন্তু", "لكن", "אבל", "danshi", "demo"),
    ("if",  "si", "si", "wenn", "se", "е́сли", "अगर", "যদি", "إذا", "אם", "ruguo", "moshi"),
    ("then","entonces", "alors", "dann", "então", "потом", "तब", "তখন", "ثم", "אז", "ranhou", "sorekara"),
    ("now", "ahora", "maintenant", "jetzt", "agora", "сейча́с", "अब", "এখন", "الآن", "עכשיו", "xianzai", "ima"),

    # numbers
    ("one",   "uno", "un", "eins", "um", "оди́н", "एक", "এক", "واحد", "אחד", "yi", "ichi"),
    ("two",   "dos", "deux", "zwei", "dois", "два", "दो", "দুই", "اثنان", "שתיים", "er", "ni"),
    ("three", "tres", "trois", "drei", "três", "три", "तीन", "তিন", "ثلاثة", "שלוש", "san", "san"),
    ("four",  "cuatro", "quatre", "vier", "quatro", "четы́ре", "चार", "চার", "أربعة", "ארבע", "si", "yon"),
    ("five",  "cinco", "cinq", "fünf", "cinco", "пять", "पाँच", "পাঁচ", "خمسة", "חמש", "wu", "go"),
    ("six",   "seis", "six", "sechs", "seis", "шесть", "छह", "ছয়", "ستة", "שש", "liu", "roku"),
    ("seven", "siete", "sept", "sieben", "sete", "семь", "सात", "সাত", "سبعة", "שבע", "qi", "nana"),
    ("eight", "ocho", "huit", "acht", "oito", "во́семь", "आठ", "আট", "ثمانية", "שמונה", "ba", "hachi"),
    ("nine",  "nueve", "neuf", "neun", "nove", "де́вять", "नौ", "নয়", "تسعة", "תשע", "jiu", "kyu"),
    ("ten",   "diez", "dix", "zehn", "dez", "де́сять", "दस", "দশ", "عشرة", "עשר", "shi", "ju"),
    ("hundred","cien", "cent", "hundert", "cem", "сто", "सौ", "একশো", "مئة", "מאה", "bai", "hyaku"),
    ("thousand","mil", "mille", "tausend", "mil", "ты́сяча", "हज़ार", "হাজার", "ألف", "אלף", "qian", "sen"),

    # time
    ("today",   "hoy", "aujourd'hui", "heute", "hoje", "сего́дня", "आज", "আজ", "اليوم", "היום", "jintian", "kyou"),
    ("tomorrow","mañana", "demain", "morgen", "amanhã", "за́втра", "कल", "আগামীকাল", "غدا", "מחר", "mingtian", "ashita"),
    ("yesterday","ayer", "hier", "gestern", "ontem", "вчера́", "कल", "গতকাল", "أمس", "אתמול", "zuotian", "kinou"),
    ("day",     "día", "jour", "Tag", "dia", "день", "दिन", "দিন", "يوم", "יום", "tian", "hi"),
    ("night",   "noche", "nuit", "Nacht", "noite", "ночь", "रात", "রাত", "ليل", "לילה", "wanshang", "yoru"),
    ("morning", "mañana", "matin", "Morgen", "manhã", "у́тро", "सुबह", "সকাল", "صباح", "בוקר", "zaoshang", "asa"),
    ("evening", "tarde", "soir", "Abend", "tarde", "ве́чер", "शाम", "সন্ধ্যা", "مساء", "ערב", "wanshang", "yuugata"),
    ("week",    "semana", "semaine", "Woche", "semana", "неде́ля", "सप्ताह", "সপ্তাহ", "أسبوع", "שבוע", "xingqi", "shuu"),
    ("month",   "mes", "mois", "Monat", "mês", "ме́сяц", "महीना", "মাস", "شهر", "חודש", "yue", "tsuki"),
    ("year",    "año", "année", "Jahr", "ano", "год", "साल", "বছর", "سنة", "שנה", "nian", "toshi"),
    ("hour",    "hora", "heure", "Stunde", "hora", "час", "घंटा", "ঘণ্টা", "ساعة", "שעה", "xiaoshi", "jikan"),
    ("minute",  "minuto", "minute", "Minute", "minuto", "мину́та", "मिनट", "মিনিট", "دقيقة", "דקה", "fenzhong", "fun"),
    ("time",    "tiempo", "temps", "Zeit", "tempo", "вре́мя", "समय", "সময়", "وقت", "זמן", "shijian", "jikan"),

    # days of the week
    ("monday",   "lunes", "lundi", "Montag", "segunda", "понеде́льник", "सोमवार", "সোমবার", "الإثنين", "יום שני", "xingqiyi", "getsuyoubi"),
    ("tuesday",  "martes", "mardi", "Dienstag", "terça", "вто́рник", "मंगलवार", "মঙ্গলবার", "الثلاثاء", "יום שלישי", "xingqier", "kayoubi"),
    ("wednesday","miércoles", "mercredi", "Mittwoch", "quarta", "среда́", "बुधवार", "বুধবার", "الأربعاء", "יום רביעי", "xingqisan", "suiyoubi"),
    ("thursday", "jueves", "jeudi", "Donnerstag", "quinta", "четве́рг", "गुरुवार", "বৃহস্পতিবার", "الخميس", "יום חמישי", "xingqisi", "mokuyoubi"),
    ("friday",   "viernes", "vendredi", "Freitag", "sexta", "пя́тница", "शुक्रवार", "শুক্রবার", "الجمعة", "יום שישי", "xingqiwu", "kinyoubi"),
    ("saturday", "sábado", "samedi", "Samstag", "sábado", "суббо́та", "शनिवार", "শনিবার", "السبت", "שבת", "xingqiliu", "doyoubi"),
    ("sunday",   "domingo", "dimanche", "Sonntag", "domingo", "воскресе́нье", "रविवार", "রবিবার", "الأحد", "יום ראשון", "xingqitian", "nichiyoubi"),

    # core nouns
    ("water",   "agua", "eau", "Wasser", "água", "вода́", "पानी", "জল", "ماء", "מים", "shui", "mizu"),
    ("food",    "comida", "nourriture", "Essen", "comida", "еда́", "खाना", "খাবার", "طعام", "אוכל", "shiwu", "tabemono"),
    ("bread",   "pan", "pain", "Brot", "pão", "хлеб", "रोटी", "রুটি", "خبز", "לחם", "mianbao", "pan"),
    ("milk",    "leche", "lait", "Milch", "leite", "молоко́", "दूध", "দুধ", "حليب", "חלב", "niunai", "miruku"),
    ("coffee",  "café", "café", "Kaffee", "café", "ко́фе", "कॉफ़ी", "কফি", "قهوة", "קפה", "kafei", "koohii"),
    ("tea",     "té", "thé", "Tee", "chá", "чай", "चाय", "চা", "شاي", "תה", "cha", "ocha"),
    ("house",   "casa", "maison", "Haus", "casa", "дом", "घर", "বাড়ি", "بيت", "בית", "fangzi", "ie"),
    ("home",    "hogar", "foyer", "Zuhause", "lar", "дом", "घर", "বাসা", "منزل", "בית", "jia", "uchi"),
    ("school",  "escuela", "école", "Schule", "escola", "шко́ла", "स्कूल", "স্কুল", "مدرسة", "בית ספר", "xuexiao", "gakkou"),
    ("work",    "trabajo", "travail", "Arbeit", "trabalho", "рабо́та", "काम", "কাজ", "عمل", "עבודה", "gongzuo", "shigoto"),
    ("city",    "ciudad", "ville", "Stadt", "cidade", "го́род", "शहर", "শহর", "مدينة", "עיר", "chengshi", "machi"),
    ("country", "país", "pays", "Land", "país", "страна́", "देश", "দেশ", "بلد", "ארץ", "guojia", "kuni"),
    ("street",  "calle", "rue", "Straße", "rua", "у́лица", "सड़क", "রাস্তা", "شارع", "רחוב", "jie", "michi"),
    ("car",     "coche", "voiture", "Auto", "carro", "маши́на", "गाड़ी", "গাড়ি", "سيارة", "מכונית", "qiche", "kuruma"),
    ("book",    "libro", "livre", "Buch", "livro", "кни́га", "किताब", "বই", "كتاب", "ספר", "shu", "hon"),
    ("phone",   "teléfono", "téléphone", "Telefon", "telefone", "телефо́н", "फ़ोन", "ফোন", "هاتف", "טלפון", "dianhua", "denwa"),
    ("computer","computadora", "ordinateur", "Computer", "computador", "компью́тер", "कंप्यूटर", "কম্পিউটার", "حاسوب", "מחשב", "diannao", "konpyuutaa"),
    ("man",     "hombre", "homme", "Mann", "homem", "мужчи́на", "आदमी", "মানুষ", "رجل", "איש", "nanren", "otoko"),
    ("woman",   "mujer", "femme", "Frau", "mulher", "же́нщина", "औरत", "মহিলা", "امرأة", "אישה", "nüren", "onna"),
    ("child",   "niño", "enfant", "Kind", "criança", "ребёнок", "बच्चा", "শিশু", "طفل", "ילד", "haizi", "kodomo"),
    ("friend",  "amigo", "ami", "Freund", "amigo", "друг", "दोस्त", "বন্ধু", "صديق", "חבר", "pengyou", "tomodachi"),
    ("family",  "familia", "famille", "Familie", "família", "семья́", "परिवार", "পরিবার", "عائلة", "משפחה", "jiating", "kazoku"),
    ("name",    "nombre", "nom", "Name", "nome", "и́мя", "नाम", "নাম", "اسم", "שם", "mingzi", "namae"),
    ("love",    "amor", "amour", "Liebe", "amor", "любо́вь", "प्यार", "ভালোবাসা", "حب", "אהבה", "ai", "ai"),
    ("life",    "vida", "vie", "Leben", "vida", "жизнь", "जीवन", "জীবন", "حياة", "חיים", "shenghuo", "jinsei"),
    ("world",   "mundo", "monde", "Welt", "mundo", "мир", "दुनिया", "পৃথিবী", "عالم", "עולם", "shijie", "sekai"),
    ("sun",     "sol", "soleil", "Sonne", "sol", "со́лнце", "सूरज", "সূর্য", "شمس", "שמש", "taiyang", "taiyou"),
    ("moon",    "luna", "lune", "Mond", "lua", "луна́", "चाँद", "চাঁদ", "قمر", "ירח", "yueliang", "tsuki"),
    ("star",    "estrella", "étoile", "Stern", "estrela", "звезда́", "सितारा", "তারা", "نجم", "כוכב", "xingxing", "hoshi"),
    ("sky",     "cielo", "ciel", "Himmel", "céu", "не́бо", "आसमान", "আকাশ", "سماء", "שמיים", "tiankong", "sora"),
    ("sea",     "mar", "mer", "Meer", "mar", "мо́ре", "समुद्र", "সমুদ্র", "بحر", "ים", "hai", "umi"),
    ("river",   "río", "rivière", "Fluss", "rio", "река́", "नदी", "নদী", "نهر", "נהר", "he", "kawa"),
    ("tree",    "árbol", "arbre", "Baum", "árvore", "де́рево", "पेड़", "গাছ", "شجرة", "עץ", "shu", "ki"),
    ("flower",  "flor", "fleur", "Blume", "flor", "цвето́к", "फूल", "ফুল", "زهرة", "פרח", "hua", "hana"),
    ("dog",     "perro", "chien", "Hund", "cachorro", "соба́ка", "कुत्ता", "কুকুর", "كلب", "כלב", "gou", "inu"),
    ("cat",     "gato", "chat", "Katze", "gato", "ко́шка", "बिल्ली", "বিড়াল", "قطة", "חתול", "mao", "neko"),
    ("bird",    "pájaro", "oiseau", "Vogel", "pássaro", "пти́ца", "पक्षी", "পাখি", "طائر", "ציפור", "niao", "tori"),
    ("fish",    "pez", "poisson", "Fisch", "peixe", "ры́ба", "मछली", "মাছ", "سمك", "דג", "yu", "sakana"),
    ("door",    "puerta", "porte", "Tür", "porta", "дверь", "दरवाज़ा", "দরজা", "باب", "דלת", "men", "doa"),
    ("window",  "ventana", "fenêtre", "Fenster", "janela", "окно́", "खिड़की", "জানালা", "نافذة", "חלון", "chuanghu", "mado"),
    ("table",   "mesa", "table", "Tisch", "mesa", "стол", "मेज़", "টেবিল", "طاولة", "שולחן", "zhuozi", "teeburu"),
    ("chair",   "silla", "chaise", "Stuhl", "cadeira", "стул", "कुर्सी", "চেয়ার", "كرسي", "כיסא", "yizi", "isu"),
    ("money",   "dinero", "argent", "Geld", "dinheiro", "де́ньги", "पैसा", "টাকা", "مال", "כסף", "qian", "okane"),
    ("road",    "camino", "route", "Straße", "estrada", "доро́га", "रास्ता", "পথ", "طريق", "דרך", "lu", "michi"),
    ("light",   "luz", "lumière", "Licht", "luz", "свет", "रोशनी", "আলো", "ضوء", "אור", "guang", "hikari"),
    ("music",   "música", "musique", "Musik", "música", "му́зыка", "संगीत", "সঙ্গীত", "موسيقى", "מוזיקה", "yinyue", "ongaku"),
    ("language","idioma", "langue", "Sprache", "idioma", "язы́к", "भाषा", "ভাষা", "لغة", "שפה", "yuyan", "gengo"),

    # core verbs (infinitive form)
    ("be",      "ser", "être", "sein", "ser", "быть", "होना", "হওয়া", "كان", "להיות", "shi", "iru"),
    ("have",    "tener", "avoir", "haben", "ter", "име́ть", "होना", "থাকা", "يملك", "יש", "you", "motsu"),
    ("do",      "hacer", "faire", "tun", "fazer", "де́лать", "करना", "করা", "فعل", "לעשות", "zuo", "suru"),
    ("go",      "ir", "aller", "gehen", "ir", "идти́", "जाना", "যাওয়া", "ذهب", "ללכת", "qu", "iku"),
    ("come",    "venir", "venir", "kommen", "vir", "приходи́ть", "आना", "আসা", "أتى", "לבוא", "lai", "kuru"),
    ("see",     "ver", "voir", "sehen", "ver", "ви́деть", "देखना", "দেখা", "رأى", "לראות", "kan", "miru"),
    ("hear",    "oír", "entendre", "hören", "ouvir", "слы́шать", "सुनना", "শোনা", "سمع", "לשמוע", "ting", "kiku"),
    ("speak",   "hablar", "parler", "sprechen", "falar", "говори́ть", "बोलना", "বলা", "تكلم", "לדבר", "shuo", "hanasu"),
    ("read",    "leer", "lire", "lesen", "ler", "чита́ть", "पढ़ना", "পড়া", "قرأ", "לקרוא", "du", "yomu"),
    ("write",   "escribir", "écrire", "schreiben", "escrever", "писа́ть", "लिखना", "লেখা", "كتب", "לכתוב", "xie", "kaku"),
    ("eat",     "comer", "manger", "essen", "comer", "есть", "खाना", "খাওয়া", "أكل", "לאכול", "chi", "taberu"),
    ("drink",   "beber", "boire", "trinken", "beber", "пить", "पीना", "পান করা", "شرب", "לשתות", "he", "nomu"),
    ("sleep",   "dormir", "dormir", "schlafen", "dormir", "спать", "सोना", "ঘুমানো", "نام", "לישון", "shuijiao", "neru"),
    ("walk",    "caminar", "marcher", "laufen", "andar", "идти́", "चलना", "হাঁটা", "مشى", "ללכת", "zou", "aruku"),
    ("run",     "correr", "courir", "rennen", "correr", "бе́гать", "दौड़ना", "দৌড়ানো", "ركض", "לרוץ", "pao", "hashiru"),
    ("buy",     "comprar", "acheter", "kaufen", "comprar", "купи́ть", "खरीदना", "কেনা", "اشترى", "לקנות", "mai", "kau"),
    ("sell",    "vender", "vendre", "verkaufen", "vender", "продава́ть", "बेचना", "বিক্রি করা", "باع", "למכור", "mai", "uru"),
    ("give",    "dar", "donner", "geben", "dar", "дава́ть", "देना", "দেওয়া", "أعطى", "לתת", "gei", "ageru"),
    ("take",    "tomar", "prendre", "nehmen", "pegar", "брать", "लेना", "নেওয়া", "أخذ", "לקחת", "na", "toru"),
    ("make",    "hacer", "faire", "machen", "fazer", "де́лать", "बनाना", "বানানো", "صنع", "ליצור", "zuo", "tsukuru"),
    ("know",    "saber", "savoir", "wissen", "saber", "знать", "जानना", "জানা", "علم", "לדעת", "zhidao", "shiru"),
    ("think",   "pensar", "penser", "denken", "pensar", "ду́мать", "सोचना", "ভাবা", "فكر", "לחשוב", "xiang", "omou"),
    ("want",    "querer", "vouloir", "wollen", "querer", "хоте́ть", "चाहना", "চাওয়া", "أراد", "לרצות", "yao", "hoshii"),
    ("need",    "necesitar", "avoir besoin", "brauchen", "precisar", "нужда́ться", "ज़रूरत होना", "প্রয়োজন", "احتاج", "להזדקק", "xuyao", "hitsuyou"),
    ("like",    "gustar", "aimer", "mögen", "gostar", "нра́виться", "पसंद करना", "পছন্দ করা", "أحب", "לחבב", "xihuan", "suki"),
    ("love",    "amar", "aimer", "lieben", "amar", "люби́ть", "प्यार करना", "ভালোবাসা", "أحب", "לאהוב", "ai", "aisuru"),
    ("help",    "ayudar", "aider", "helfen", "ajudar", "помога́ть", "मदद करना", "সাহায্য করা", "ساعد", "לעזור", "bangzhu", "tasukeru"),
    ("open",    "abrir", "ouvrir", "öffnen", "abrir", "открыва́ть", "खोलना", "খোলা", "فتح", "לפתוח", "kai", "akeru"),
    ("close",   "cerrar", "fermer", "schließen", "fechar", "закрыва́ть", "बंद करना", "বন্ধ করা", "أغلق", "לסגור", "guan", "shimeru"),
    ("start",   "empezar", "commencer", "anfangen", "começar", "начина́ть", "शुरू करना", "শুরু করা", "بدأ", "להתחיל", "kaishi", "hajimeru"),
    ("stop",    "parar", "arrêter", "stoppen", "parar", "остана́вливать", "रुकना", "থামা", "توقف", "לעצור", "ting", "tomeru"),
    ("find",    "encontrar", "trouver", "finden", "encontrar", "находи́ть", "ढूँढना", "খোঁজা", "وجد", "למצוא", "zhao", "mitsukeru"),
    ("ask",     "preguntar", "demander", "fragen", "perguntar", "спра́шивать", "पूछना", "জিজ্ঞাসা করা", "سأل", "לשאול", "wen", "kiku"),
    ("answer",  "responder", "répondre", "antworten", "responder", "отвеча́ть", "जवाब देना", "উত্তর দেওয়া", "أجاب", "לענות", "huida", "kotaeru"),

    # adjectives
    ("good",    "bueno", "bon", "gut", "bom", "хоро́ший", "अच्छा", "ভালো", "جيد", "טוב", "hao", "ii"),
    ("bad",     "malo", "mauvais", "schlecht", "mau", "плохо́й", "बुरा", "খারাপ", "سيء", "רע", "huai", "warui"),
    ("big",     "grande", "grand", "groß", "grande", "большо́й", "बड़ा", "বড়", "كبير", "גדול", "da", "ookii"),
    ("small",   "pequeño", "petit", "klein", "pequeno", "ма́ленький", "छोटा", "ছোট", "صغير", "קטן", "xiao", "chiisai"),
    ("new",     "nuevo", "nouveau", "neu", "novo", "но́вый", "नया", "নতুন", "جديد", "חדש", "xin", "atarashii"),
    ("old",     "viejo", "vieux", "alt", "velho", "ста́рый", "पुराना", "পুরানো", "قديم", "ישן", "lao", "furui"),
    ("hot",     "caliente", "chaud", "heiß", "quente", "горя́чий", "गरम", "গরম", "حار", "חם", "re", "atsui"),
    ("cold",    "frío", "froid", "kalt", "frio", "холо́дный", "ठंडा", "ঠান্ডা", "بارد", "קר", "leng", "samui"),
    ("happy",   "feliz", "heureux", "glücklich", "feliz", "счастли́вый", "खुश", "খুশি", "سعيد", "שמח", "kaixin", "ureshii"),
    ("sad",     "triste", "triste", "traurig", "triste", "гру́стный", "उदास", "দুঃখিত", "حزين", "עצוב", "shangxin", "kanashii"),
    ("fast",    "rápido", "rapide", "schnell", "rápido", "бы́стрый", "तेज़", "দ্রুত", "سريع", "מהיר", "kuai", "hayai"),
    ("slow",    "lento", "lent", "langsam", "lento", "ме́дленный", "धीमा", "ধীর", "بطيء", "איטי", "man", "osoi"),
    ("beautiful","hermoso", "beau", "schön", "bonito", "краси́вый", "सुंदर", "সুন্দর", "جميل", "יפה", "meili", "utsukushii"),
    ("easy",    "fácil", "facile", "einfach", "fácil", "лёгкий", "आसान", "সহজ", "سهل", "קל", "rongyi", "yasashii"),
    ("hard",    "difícil", "difficile", "schwer", "difícil", "тру́дный", "कठिन", "কঠিন", "صعب", "קשה", "nan", "muzukashii"),
    ("right",   "correcto", "correct", "richtig", "certo", "пра́вильный", "सही", "সঠিক", "صحيح", "נכון", "duide", "tadashii"),
    ("wrong",   "incorrecto", "faux", "falsch", "errado", "неправ́ильный", "गलत", "ভুল", "خاطئ", "שגוי", "cuode", "machigai"),
    ("first",   "primero", "premier", "erste", "primeiro", "пе́рвый", "पहला", "প্রথম", "أول", "ראשון", "diyi", "ichiban"),
    ("last",    "último", "dernier", "letzte", "último", "после́дний", "आख़िरी", "শেষ", "أخير", "אחרון", "zuihou", "saigo"),
    ("long",    "largo", "long", "lang", "longo", "дли́нный", "लंबा", "লম্বা", "طويل", "ארוך", "chang", "nagai"),
    ("short",   "corto", "court", "kurz", "curto", "коро́ткий", "छोटा", "ছোট", "قصير", "קצר", "duan", "mijikai"),

    # phrases
    ("good morning",   "buenos días", "bonjour", "guten Morgen", "bom dia", "до́брое у́тро", "सुप्रभात", "শুভ সকাল", "صباح الخير", "בוקר טוב", "zaoshang hao", "ohayou"),
    ("good night",     "buenas noches", "bonne nuit", "gute Nacht", "boa noite", "споко́йной но́чи", "शुभ रात्रि", "শুভ রাত্রি", "تصبح على خير", "לילה טוב", "wan'an", "oyasumi"),
    ("thank you",      "gracias", "merci", "danke", "obrigado", "спаси́бо", "धन्यवाद", "ধন্যবাদ", "شكرا", "תודה", "xiexie", "arigatou"),
    ("please",         "por favor", "s'il vous plaît", "bitte", "por favor", "пожа́луйста", "कृपया", "অনুগ্রহ করে", "من فضلك", "בבקשה", "qing", "onegai"),
    ("excuse me",      "disculpe", "excusez-moi", "entschuldigung", "com licença", "извини́те", "क्षमा करें", "মাফ করবেন", "عذرا", "סליחה", "duibuqi", "sumimasen"),
    ("hello",          "hola", "bonjour", "hallo", "olá", "приве́т", "नमस्ते", "নমস্কার", "مرحبا", "שלום", "ni hao", "konnichiwa"),
    ("goodbye",        "adiós", "au revoir", "tschüss", "tchau", "до свида́ния", "अलविदा", "বিদায়", "وداعا", "להתראות", "zaijian", "sayounara"),
    ("how are you",    "cómo estás", "comment ça va", "wie geht es dir", "como vai", "как дела́", "कैसे हो", "কেমন আছ", "كيف حالك", "מה שלומך", "ni hao ma", "ogenki desu ka"),
    ("i love you",     "te amo", "je t'aime", "ich liebe dich", "eu te amo", "я тебя́ люблю́", "मैं तुमसे प्यार करता हूँ", "আমি তোমাকে ভালোবাসি", "أحبك", "אני אוהב אותך", "wo ai ni", "aishiteru"),
    ("see you later",  "hasta luego", "à plus tard", "bis später", "até logo", "до встре́чи", "बाद में मिलते हैं", "পরে দেখা হবে", "أراك لاحقا", "נתראה", "huitou jian", "mata atode"),
    ("welcome",        "bienvenido", "bienvenue", "willkommen", "bem-vindo", "добро́ пожа́ловать", "स्वागत है", "স্বাগতম", "أهلا", "ברוך הבא", "huanying", "youkoso"),
    ("sorry",          "lo siento", "désolé", "entschuldigung", "desculpe", "извини́", "माफ़ कीजिए", "দুঃখিত", "آسف", "סליחה", "duibuqi", "gomen"),
]

LANG_INDEX = {
    "en": 0, "es": 1, "fr": 2, "de": 3, "pt": 4, "ru": 5,
    "hi": 6, "bn": 7, "ar": 8, "he": 9, "zh": 10, "ja": 11
}

PAIRS = [
    ("en","he"), ("he","en"),
    ("en","ar"), ("ar","en"),
    ("en","zh"), ("zh","en"),
    ("en","es"), ("es","en"),
    ("en","hi"), ("hi","en"),
    ("en","pt"), ("pt","en"),
    ("en","bn"), ("bn","en"),
    ("en","ru"), ("ru","en"),
    ("en","ja"), ("ja","en"),
    ("en","fr"), ("fr","en"),
    ("en","de"), ("de","en"),
    ("he","ar"), ("ar","he"),
]

def build_pair(src, dst):
    si, di = LANG_INDEX[src], LANG_INDEX[dst]
    out = {}
    for row in ROWS:
        key = row[si].strip().lower()
        val = row[di].strip()
        if key and val and key not in out:
            out[key] = val
    return out

written = 0
for src, dst in PAIRS:
    data = build_pair(src, dst)
    path = OUT / f"translations_{src}_{dst}.json"
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        f.write("\n")
    written += 1
    print(f"wrote {path.name}: {len(data)} entries")

print(f"\nTotal: {written} files in {OUT}")
