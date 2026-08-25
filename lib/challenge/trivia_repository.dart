import 'dart:math';

import 'trivia_card.dart';
import 'trivia_deck.dart';

/// Repository of all trivia questions for the TurtleKing Trivia Deck.
///
/// Contains approximately 100+ questions across:
/// - Standard categories (General Knowledge, Geography, History, etc.)
/// - Personal/Group questions
/// - A-Z category questions
/// - Rapid Fire questions
class TriviaRepository {
  TriviaRepository._();

  /// Returns a new shuffled deck of all trivia cards.
  static TriviaDeck newDeck({Random? random}) {
    return TriviaDeck(allCards, random: random);
  }

  /// All trivia cards in the repository.
  static final List<TriviaCard> allCards = [
    // =========================================================================
    // GENERAL KNOWLEDGE
    // =========================================================================
    TriviaCard(
      id: 'gk-001',
      category: TriviaCategory.generalKnowledge,
      question: 'What is the capital of France?',
      answer: 'Paris',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'gk-002',
      category: TriviaCategory.generalKnowledge,
      question: 'How many continents are there on Earth?',
      answer: '7',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'gk-003',
      category: TriviaCategory.generalKnowledge,
      question: 'What is the largest ocean on Earth?',
      answer: 'Pacific Ocean',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'gk-004',
      category: TriviaCategory.generalKnowledge,
      question: 'What year did the Titanic sink?',
      answer: '1912',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'gk-005',
      category: TriviaCategory.generalKnowledge,
      question: 'What is the chemical symbol for gold?',
      answer: 'Au',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'gk-006',
      category: TriviaCategory.generalKnowledge,
      question: 'Who painted the Mona Lisa?',
      answer: 'Leonardo da Vinci',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'gk-007',
      category: TriviaCategory.generalKnowledge,
      question: 'What is the smallest prime number?',
      answer: '2',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'gk-008',
      category: TriviaCategory.generalKnowledge,
      question: 'How many bones are in the human body?',
      answer: '206',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'gk-009',
      category: TriviaCategory.generalKnowledge,
      question: 'What planet is known as the Red Planet?',
      answer: 'Mars',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'gk-010',
      category: TriviaCategory.generalKnowledge,
      question: 'What is the speed of light in km/s?',
      answer: '299,792',
      difficulty: TriviaDifficulty.hard,
    ),

    // =========================================================================
    // GEOGRAPHY
    // =========================================================================
    TriviaCard(
      id: 'geo-001',
      category: TriviaCategory.geography,
      question: 'What is the largest country by area?',
      answer: 'Russia',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'geo-002',
      category: TriviaCategory.geography,
      question: 'Which river is the longest in the world?',
      answer: 'Nile',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'geo-003',
      category: TriviaCategory.geography,
      question: 'What is the capital of Japan?',
      answer: 'Tokyo',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'geo-004',
      category: TriviaCategory.geography,
      question: 'Which desert is the largest hot desert?',
      answer: 'Sahara',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'geo-005',
      category: TriviaCategory.geography,
      question: 'How many countries are in Africa?',
      answer: '54',
      difficulty: TriviaDifficulty.hard,
    ),
    TriviaCard(
      id: 'geo-006',
      category: TriviaCategory.geography,
      question: 'What is the capital of Australia?',
      answer: 'Canberra',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'geo-007',
      category: TriviaCategory.geography,
      question: 'Which country has the most people?',
      answer: 'India',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'geo-008',
      category: TriviaCategory.geography,
      question: 'What is the smallest country in the world?',
      answer: 'Vatican City',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'geo-009',
      category: TriviaCategory.geography,
      question: 'Mount Everest is on the border of which two countries?',
      answer: 'Nepal and China',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'geo-010',
      category: TriviaCategory.geography,
      question: 'What is the deepest lake in the world?',
      answer: 'Lake Baikal',
      difficulty: TriviaDifficulty.hard,
    ),

    // =========================================================================
    // HISTORY
    // =========================================================================
    TriviaCard(
      id: 'hist-001',
      category: TriviaCategory.history,
      question: 'In what year did World War II end?',
      answer: '1945',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'hist-002',
      category: TriviaCategory.history,
      question: 'Who was the first President of the United States?',
      answer: 'George Washington',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'hist-003',
      category: TriviaCategory.history,
      question: 'What ancient wonder was located in Giza, Egypt?',
      answer: 'Great Pyramid',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'hist-004',
      category: TriviaCategory.history,
      question: 'Which empire was ruled by Genghis Khan?',
      answer: 'Mongol Empire',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'hist-005',
      category: TriviaCategory.history,
      question: 'What year did Kenya gain independence?',
      answer: '1963',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'hist-006',
      category: TriviaCategory.history,
      question: 'Who was the first person to walk on the moon?',
      answer: 'Neil Armstrong',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'hist-007',
      category: TriviaCategory.history,
      question: 'What was the Renaissance?',
      answer: 'Cultural rebirth in Europe',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'hist-008',
      category: TriviaCategory.history,
      question: 'Which ancient civilization built Machu Picchu?',
      answer: 'Inca',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'hist-009',
      category: TriviaCategory.history,
      question: 'What year did the Berlin Wall fall?',
      answer: '1989',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'hist-010',
      category: TriviaCategory.history,
      question: 'Who wrote the Declaration of Independence?',
      answer: 'Thomas Jefferson',
      difficulty: TriviaDifficulty.medium,
    ),

    // =========================================================================
    // SCIENCE
    // =========================================================================
    TriviaCard(
      id: 'sci-001',
      category: TriviaCategory.science,
      question: 'What gas do plants absorb from the atmosphere?',
      answer: 'Carbon dioxide',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'sci-002',
      category: TriviaCategory.science,
      question: 'What is the powerhouse of the cell?',
      answer: 'Mitochondria',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'sci-003',
      category: TriviaCategory.science,
      question: 'What is the chemical formula for water?',
      answer: 'H2O',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'sci-004',
      category: TriviaCategory.science,
      question: 'What planet has the most moons?',
      answer: 'Saturn',
      difficulty: TriviaDifficulty.hard,
    ),
    TriviaCard(
      id: 'sci-005',
      category: TriviaCategory.science,
      question: 'What is the hardest natural substance?',
      answer: 'Diamond',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'sci-006',
      category: TriviaCategory.science,
      question: 'How many elements are in the periodic table?',
      answer: '118',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'sci-007',
      category: TriviaCategory.science,
      question: 'What force keeps us on the ground?',
      answer: 'Gravity',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'sci-008',
      category: TriviaCategory.science,
      question: 'What is the boiling point of water in Celsius?',
      answer: '100',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'sci-009',
      category: TriviaCategory.science,
      question: 'What is the most abundant gas in Earth\'s atmosphere?',
      answer: 'Nitrogen',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'sci-010',
      category: TriviaCategory.science,
      question: 'What type of animal is a dolphin?',
      answer: 'Mammal',
      difficulty: TriviaDifficulty.easy,
    ),

    // =========================================================================
    // TECHNOLOGY
    // =========================================================================
    TriviaCard(
      id: 'tech-001',
      category: TriviaCategory.technology,
      question: 'What does "HTTP" stand for?',
      answer: 'HyperText Transfer Protocol',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'tech-002',
      category: TriviaCategory.technology,
      question: 'Who co-founded Apple Computer?',
      answer: 'Steve Jobs',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'tech-003',
      category: TriviaCategory.technology,
      question: 'What does "CPU" stand for?',
      answer: 'Central Processing Unit',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'tech-004',
      category: TriviaCategory.technology,
      question: 'What year was the first iPhone released?',
      answer: '2007',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'tech-005',
      category: TriviaCategory.technology,
      question: 'What does "AI" stand for?',
      answer: 'Artificial Intelligence',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'tech-006',
      category: TriviaCategory.technology,
      question: 'What programming language is Flutter built with?',
      answer: 'Dart',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'tech-007',
      category: TriviaCategory.technology,
      question: 'What does "URL" stand for?',
      answer: 'Uniform Resource Locator',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'tech-008',
      category: TriviaCategory.technology,
      question: 'Who is known as the father of the World Wide Web?',
      answer: 'Tim Berners-Lee',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'tech-009',
      category: TriviaCategory.technology,
      question: 'What does "Wi-Fi" stand for?',
      answer: 'Wireless Fidelity',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'tech-010',
      category: TriviaCategory.technology,
      question: 'What company developed the Android operating system?',
      answer: 'Google',
      difficulty: TriviaDifficulty.easy,
    ),

    // =========================================================================
    // SPORTS
    // =========================================================================
    TriviaCard(
      id: 'sport-001',
      category: TriviaCategory.sports,
      question: 'How many players are on a soccer team?',
      answer: '11',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'sport-002',
      category: TriviaCategory.sports,
      question: 'What sport is played at Wimbledon?',
      answer: 'Tennis',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'sport-003',
      category: TriviaCategory.sports,
      question: 'How many rings are on the Olympic flag?',
      answer: '5',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'sport-004',
      category: TriviaCategory.sports,
      question: 'What country won the 2022 FIFA World Cup?',
      answer: 'Argentina',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'sport-005',
      category: TriviaCategory.sports,
      question: 'How long is an Olympic swimming pool?',
      answer: '50 meters',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'sport-006',
      category: TriviaCategory.sports,
      question: 'What sport uses a shuttlecock?',
      answer: 'Badminton',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'sport-007',
      category: TriviaCategory.sports,
      question: 'Who has won the most Ballon d\'Or awards?',
      answer: 'Lionel Messi',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'sport-008',
      category: TriviaCategory.sports,
      question: 'What is the national sport of Kenya?',
      answer: 'Running',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'sport-009',
      category: TriviaCategory.sports,
      question: 'How many bases are there in baseball?',
      answer: '4',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'sport-010',
      category: TriviaCategory.sports,
      question: 'What year were the first modern Olympics held?',
      answer: '1896',
      difficulty: TriviaDifficulty.hard,
    ),

    // =========================================================================
    // MUSIC
    // =========================================================================
    TriviaCard(
      id: 'music-001',
      category: TriviaCategory.music,
      question: 'How many strings does a standard guitar have?',
      answer: '6',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'music-002',
      category: TriviaCategory.music,
      question: 'Who is known as the "King of Pop"?',
      answer: 'Michael Jackson',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'music-003',
      category: TriviaCategory.music,
      question: 'What band was Freddie Mercury the lead singer of?',
      answer: 'Queen',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'music-004',
      category: TriviaCategory.music,
      question: 'What instrument has 88 keys?',
      answer: 'Piano',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'music-005',
      category: TriviaCategory.music,
      question: 'What country is the band U2 from?',
      answer: 'Ireland',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'music-006',
      category: TriviaCategory.music,
      question: 'What is the best-selling album of all time?',
      answer: 'Thriller',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'music-007',
      category: TriviaCategory.music,
      question: 'How many members are in a quartet?',
      answer: '4',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'music-008',
      category: TriviaCategory.music,
      question: 'What instrument does a drummer play?',
      answer: 'Drums',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'music-009',
      category: TriviaCategory.music,
      question: 'What genre of music originated in New Orleans?',
      answer: 'Jazz',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'music-010',
      category: TriviaCategory.music,
      question: 'Who sang "Bohemian Rhapsody"?',
      answer: 'Queen',
      difficulty: TriviaDifficulty.easy,
    ),

    // =========================================================================
    // MOVIES & TV
    // =========================================================================
    TriviaCard(
      id: 'movie-001',
      category: TriviaCategory.moviesAndTv,
      question: 'What is the highest-grossing film of all time?',
      answer: 'Avatar',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'movie-002',
      category: TriviaCategory.moviesAndTv,
      question: 'Who played Jack in Titanic?',
      answer: 'Leonardo DiCaprio',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'movie-003',
      category: TriviaCategory.moviesAndTv,
      question: 'What year was the first Star Wars movie released?',
      answer: '1977',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'movie-004',
      category: TriviaCategory.moviesAndTv,
      question: 'What animated movie features a clownfish named Nemo?',
      answer: 'Finding Nemo',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'movie-005',
      category: TriviaCategory.moviesAndTv,
      question: 'What is the name of the school in Harry Potter?',
      answer: 'Hogwarts',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'movie-006',
      category: TriviaCategory.moviesAndTv,
      question: 'Who directed Jurassic Park?',
      answer: 'Steven Spielberg',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'movie-007',
      category: TriviaCategory.moviesAndTv,
      question: 'What superhero is Clark Kent?',
      answer: 'Superman',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'movie-008',
      category: TriviaCategory.moviesAndTv,
      question:
          'What is the name of the robot in Star Wars that says "Beep boop"?',
      answer: 'R2-D2',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'movie-009',
      category: TriviaCategory.moviesAndTv,
      question: 'What movie features the quote "Here\'s looking at you, kid"?',
      answer: 'Casablanca',
      difficulty: TriviaDifficulty.hard,
    ),
    TriviaCard(
      id: 'movie-010',
      category: TriviaCategory.moviesAndTv,
      question: 'What is the name of the kingdom in The Lion King?',
      answer: 'Pride Rock',
      difficulty: TriviaDifficulty.easy,
    ),

    // =========================================================================
    // FOOD
    // =========================================================================
    TriviaCard(
      id: 'food-001',
      category: TriviaCategory.food,
      question: 'What fruit is known as the "king of fruits"?',
      answer: 'Durian',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'food-002',
      category: TriviaCategory.food,
      question: 'What country is sushi from?',
      answer: 'Japan',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'food-003',
      category: TriviaCategory.food,
      question: 'What is the main ingredient in guacamole?',
      answer: 'Avocado',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'food-004',
      category: TriviaCategory.food,
      question: 'What type of pasta is shaped like bow ties?',
      answer: 'Farfalle',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'food-005',
      category: TriviaCategory.food,
      question: 'What is the most popular pizza topping in the US?',
      answer: 'Pepperoni',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'food-006',
      category: TriviaCategory.food,
      question: 'What grain is used to make sake?',
      answer: 'Rice',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'food-007',
      category: TriviaCategory.food,
      question: 'What is the main ingredient in hummus?',
      answer: 'Chickpeas',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'food-008',
      category: TriviaCategory.food,
      question: 'What fruit is used to make wine?',
      answer: 'Grapes',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'food-009',
      category: TriviaCategory.food,
      question: 'What is the most consumed meat in the world?',
      answer: 'Pork',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'food-010',
      category: TriviaCategory.food,
      question: 'What Italian dish means "cooked cream"?',
      answer: 'Fettuccine Alfredo',
      difficulty: TriviaDifficulty.hard,
    ),

    // =========================================================================
    // KENYA/AFRICA
    // =========================================================================
    TriviaCard(
      id: 'ka-001',
      category: TriviaCategory.kenyaAfrica,
      question: 'What is the capital of Kenya?',
      answer: 'Nairobi',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'ka-002',
      category: TriviaCategory.kenyaAfrica,
      question: 'What is the largest lake in Africa?',
      answer: 'Lake Victoria',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'ka-003',
      category: TriviaCategory.kenyaAfrica,
      question: 'What animal is known as the "Big Five" in Kenya?',
      answer: 'Lion, Leopard, Rhino, Elephant, Buffalo',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'ka-004',
      category: TriviaCategory.kenyaAfrica,
      question: 'What is the currency of Kenya?',
      answer: 'Kenyan Shilling',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'ka-005',
      category: TriviaCategory.kenyaAfrica,
      question: 'What mountain is the highest in Africa?',
      answer: 'Mount Kilimanjaro',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'ka-006',
      category: TriviaCategory.kenyaAfrica,
      question: 'What is the official language of Kenya?',
      answer: 'English and Swahili',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'ka-007',
      category: TriviaCategory.kenyaAfrica,
      question: 'What is the Great Rift Valley?',
      answer: 'A geological feature stretching from Lebanon to Mozambique',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'ka-008',
      category: TriviaCategory.kenyaAfrica,
      question:
          'What is the name of Kenya\'s famous long-distance runners\' region?',
      answer: 'Rift Valley',
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'ka-009',
      category: TriviaCategory.kenyaAfrica,
      question: 'What is the national animal of Kenya?',
      answer: 'Lion',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'ka-010',
      category: TriviaCategory.kenyaAfrica,
      question: 'What is the largest country in Africa by area?',
      answer: 'Algeria',
      difficulty: TriviaDifficulty.medium,
    ),

    // =========================================================================
    // PERSONAL / GROUP QUESTIONS
    // =========================================================================
    TriviaCard(
      id: 'personal-001',
      category: TriviaCategory.personal,
      question: 'Can you guess the crush of the person on your left?',
      answer: 'Players verify the answer',
      isPersonal: true,
      isGroupQuestion: true,
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'personal-002',
      category: TriviaCategory.personal,
      question: 'Who in this group is most likely to become famous?',
      answer: 'Players vote and discuss',
      isPersonal: true,
      isGroupQuestion: true,
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'personal-003',
      category: TriviaCategory.personal,
      question:
          'Who knows the challenged player best? What is their favorite food?',
      answer: 'Challenged player confirms',
      isPersonal: true,
      isGroupQuestion: true,
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'personal-004',
      category: TriviaCategory.personal,
      question:
          'What would the challenged player choose: a night out or a movie night?',
      answer: 'Challenged player confirms',
      isPersonal: true,
      isGroupQuestion: true,
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'personal-005',
      category: TriviaCategory.personal,
      question: 'Who in this group is the best dancer?',
      answer: 'Players vote and discuss',
      isPersonal: true,
      isGroupQuestion: true,
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'personal-006',
      category: TriviaCategory.personal,
      question: 'What is the challenged player\'s most embarrassing moment?',
      answer: 'Challenged player confirms',
      isPersonal: true,
      isGroupQuestion: true,
      difficulty: TriviaDifficulty.hard,
    ),
    TriviaCard(
      id: 'personal-007',
      category: TriviaCategory.personal,
      question: 'Who in this group would survive a zombie apocalypse?',
      answer: 'Players vote and discuss',
      isPersonal: true,
      isGroupQuestion: true,
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'personal-008',
      category: TriviaCategory.personal,
      question: 'What is the challenged player\'s hidden talent?',
      answer: 'Challenged player confirms',
      isPersonal: true,
      isGroupQuestion: true,
      difficulty: TriviaDifficulty.medium,
    ),
    TriviaCard(
      id: 'personal-009',
      category: TriviaCategory.personal,
      question:
          'Who in this group is the most likely to forget their own birthday?',
      answer: 'Players vote and discuss',
      isPersonal: true,
      isGroupQuestion: true,
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'personal-010',
      category: TriviaCategory.personal,
      question: 'What song would the challenged player sing at karaoke?',
      answer: 'Challenged player confirms',
      isPersonal: true,
      isGroupQuestion: true,
      difficulty: TriviaDifficulty.medium,
    ),

    // =========================================================================
    // A-Z TRIVIA (Countries)
    // =========================================================================
    TriviaCard(
      id: 'az-countries-001',
      category: TriviaCategory.aToZ,
      question: 'Name a country that starts with A',
      answer:
          'Australia, Argentina, Austria, Algeria, Angola, Armenia, Afghanistan, Albania...',
      aToZLetter: 'A',
      aToZCategory: 'Countries',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'az-countries-002',
      category: TriviaCategory.aToZ,
      question: 'Name a country that starts with B',
      answer:
          'Brazil, Belgium, Bolivia, Botswana, Bulgaria, Bangladesh, Burma...',
      aToZLetter: 'B',
      aToZCategory: 'Countries',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'az-countries-003',
      category: TriviaCategory.aToZ,
      question: 'Name a country that starts with C',
      answer:
          'Canada, China, Colombia, Cuba, Czech Republic, Chile, Cameroon...',
      aToZLetter: 'C',
      aToZCategory: 'Countries',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'az-countries-004',
      category: TriviaCategory.aToZ,
      question: 'Name a country that starts with K',
      answer: 'Kenya, Kazakhstan, Kuwait, Kosovo, Kyrgyzstan...',
      aToZLetter: 'K',
      aToZCategory: 'Countries',
      difficulty: TriviaDifficulty.medium,
    ),

    // =========================================================================
    // A-Z TRIVIA (Foods)
    // =========================================================================
    TriviaCard(
      id: 'az-foods-001',
      category: TriviaCategory.aToZ,
      question: 'Name a food that starts with P',
      answer: 'Pizza, Pasta, Pancakes, Pork, Peach, Pear, Potato...',
      aToZLetter: 'P',
      aToZCategory: 'Foods',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'az-foods-002',
      category: TriviaCategory.aToZ,
      question: 'Name a food that starts with C',
      answer: 'Cake, Chicken, Chocolate, Cheese, Coffee, Corn, Carrot...',
      aToZLetter: 'C',
      aToZCategory: 'Foods',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'az-foods-003',
      category: TriviaCategory.aToZ,
      question: 'Name a food that starts with S',
      answer: 'Sushi, Steak, Soup, Salad, Sandwich, Spaghetti...',
      aToZLetter: 'S',
      aToZCategory: 'Foods',
      difficulty: TriviaDifficulty.easy,
    ),

    // =========================================================================
    // A-Z TRIVIA (Animals)
    // =========================================================================
    TriviaCard(
      id: 'az-animals-001',
      category: TriviaCategory.aToZ,
      question: 'Name an animal that starts with E',
      answer: 'Elephant, Eagle, Eel, Emu, Elk...',
      aToZLetter: 'E',
      aToZCategory: 'Animals',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'az-animals-002',
      category: TriviaCategory.aToZ,
      question: 'Name an animal that starts with L',
      answer: 'Lion, Leopard, Llama, Lemur, Lobster...',
      aToZLetter: 'L',
      aToZCategory: 'Animals',
      difficulty: TriviaDifficulty.easy,
    ),

    // =========================================================================
    // RAPID FIRE
    // =========================================================================
    TriviaCard(
      id: 'rf-001',
      category: TriviaCategory.rapidFire,
      question: 'What color is the sky?',
      answer: 'Blue',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'rf-002',
      category: TriviaCategory.rapidFire,
      question: 'How many days in a week?',
      answer: '7',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'rf-003',
      category: TriviaCategory.rapidFire,
      question: 'What is 5 + 3?',
      answer: '8',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'rf-004',
      category: TriviaCategory.rapidFire,
      question: 'What animal says "meow"?',
      answer: 'Cat',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'rf-005',
      category: TriviaCategory.rapidFire,
      question: 'What is the opposite of hot?',
      answer: 'Cold',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'rf-006',
      category: TriviaCategory.rapidFire,
      question: 'Name a primary color',
      answer: 'Red, Blue, or Yellow',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'rf-007',
      category: TriviaCategory.rapidFire,
      question: 'What do you breathe?',
      answer: 'Air',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'rf-008',
      category: TriviaCategory.rapidFire,
      question: 'What is H2O?',
      answer: 'Water',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'rf-009',
      category: TriviaCategory.rapidFire,
      question: 'How many vowels in "hello"?',
      answer: '2',
      difficulty: TriviaDifficulty.easy,
    ),
    TriviaCard(
      id: 'rf-010',
      category: TriviaCategory.rapidFire,
      question: 'What shape is a stop sign?',
      answer: 'Octagon',
      difficulty: TriviaDifficulty.easy,
    ),
  ];
}
