import 'dart:math';

import 'dare_card.dart';
import 'dare_deck.dart';

/// Provides the complete TurtleKing Dare Deck.
///
/// All cards are created once and exposed via [allCards]. Use [newDeck] to
/// get a fresh shuffled deck for a new game session.
class DareRepository {
  DareRepository._();

  /// All dare cards in the TurtleKing deck.
  static final List<DareCard> allCards = [
    // ═══════════════════════════════════════════════════════════
    // RISK — 25 cards
    // ═══════════════════════════════════════════════════════════
    DareCard(
      id: 'risk-001',
      category: DareCategory.risk,
      title: 'Blind Taste Test',
      description:
          'Close your eyes and taste whatever the group puts in front of you. If you refuse, take a shot.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'risk-002',
      category: DareCategory.risk,
      title: 'Phone Roulette',
      description:
          'Open your camera roll and show the group your most recent 5 photos. No deletions allowed.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'risk-003',
      category: DareCategory.risk,
      title: 'Let Someone Post',
      description:
          'Give your phone to another player. They post whatever they want on your social media (within reason). You have 30 seconds to stop them or it stays.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'risk-004',
      category: DareCategory.risk,
      title: 'Dramatic Confession',
      description:
          'Make up the most dramatic, over-the-top confession about something ridiculous. The group votes on whether it was convincing enough.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'risk-005',
      category: DareCategory.risk,
      title: 'Accent Challenge',
      description:
          'Speak in a ridiculous accent for the next 2 minutes. If anyone catches you dropping the accent, take a shot.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'risk-006',
      category: DareCategory.risk,
      title: 'Sing Your Orders',
      description:
          'From now until your next turn, you must sing every sentence like it is a musical number.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'risk-007',
      category: DareCategory.risk,
      title: 'Truth Bomb',
      description:
          'Answer one question from the group honestly. No dodging, no "pass". The group decides if you were truthful enough.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'risk-008',
      category: DareCategory.risk,
      title: 'Social Media Switch',
      description:
          'Change your profile picture to whatever the group chooses and keep it for 24 hours.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'risk-009',
      category: DareCategory.risk,
      title: 'Roast Battle',
      description:
          'Pick another player and deliver a 30-second roast. They get to roast you back. The group votes on the winner.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'risk-010',
      category: DareCategory.risk,
      title: 'Secret Revealer',
      description:
          'Tell the group one thing about yourself that you have never told anyone. It must be true.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'risk-011',
      category: DareCategory.risk,
      title: 'Deadpan Challenge',
      description:
          'Maintain perfect eye contact with the person across from you for 60 seconds without laughing or looking away.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'risk-012',
      category: DareCategory.risk,
      title: 'Improv Rap',
      description:
          'Freestyle rap for 30 seconds about the person to your left. It must rhyme and have a beat.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'risk-013',
      category: DareCategory.risk,
      title: 'Spice Roulette',
      description:
          'Take a sip of the spiciest drink the group can make. If you refuse, take a shot instead.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'risk-014',
      category: DareCategory.risk,
      title: 'Alien Abduction',
      description:
          'Act out being abducted by aliens for 30 seconds. Full commitment — screaming, wiggling, the works.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'risk-015',
      category: DareCategory.risk,
      title: 'The Compliment Gauntlet',
      description:
          'Give every other player a genuine, heartfelt compliment. No sarcasm allowed.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'risk-016',
      category: DareCategory.risk,
      title: 'Dance-Off',
      description:
          'Perform a 30-second solo dance. The group judges on creativity, enthusiasm, and overall vibes.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'risk-017',
      category: DareCategory.risk,
      title: 'Flashback',
      description:
          'Tell the most embarrassing story from your life. The group decides if it was embarrassing enough.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'risk-018',
      category: DareCategory.risk,
      title: 'Speed Dating',
      description:
          'You have 15 seconds to deliver the most convincing pickup line to each player at the table.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'risk-019',
      category: DareCategory.risk,
      title: 'Mirror Mirror',
      description:
          'Another player does a series of 5 random facial expressions and you must perfectly mirror each one within 2 seconds.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'risk-020',
      category: DareCategory.risk,
      title: 'Impression Master',
      description:
          'Do an impression of another player at the table. They must rate your performance out of 10.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'risk-021',
      category: DareCategory.risk,
      title: 'Speed Round',
      description:
          'Name 5 things in a category chosen by the group in 10 seconds. Fail and take a shot.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'risk-022',
      category: DareCategory.risk,
      title: 'Honest opinions',
      description:
          'Say one honest opinion about something in pop culture that you think is overrated. Be passionate about it.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'risk-023',
      category: DareCategory.risk,
      title: 'Song Dedication',
      description:
          'Pick another player and dedicate a song to them. You must sing at least the chorus.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'risk-024',
      category: DareCategory.risk,
      title: 'Act It Out',
      description:
          'Another player names a movie scene. You must act it out with full dramatic energy for 30 seconds.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'risk-025',
      category: DareCategory.risk,
      title: 'Crowd Pleaser',
      description:
          'Tell a joke. If nobody laughs, take a shot. You get 60 seconds.',
      difficulty: DareDifficulty.hard,
    ),

    // ═══════════════════════════════════════════════════════════
    // SOCIAL — 20 cards
    // ═══════════════════════════════════════════════════════════
    DareCard(
      id: 'social-001',
      category: DareCategory.social,
      title: 'Group Huddle',
      description:
          'Everyone must group hug for 10 seconds while you say something sweet about each person.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'social-002',
      category: DareCategory.social,
      title: 'High Five Champion',
      description:
          'Give a dramatic, exaggerated high five to every other player. Each one must be uniquely styled.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'social-003',
      category: DareCategory.social,
      title: 'Compliment Chain',
      description:
          'Start a compliment chain. You compliment Player 1, Player 1 compliments Player 2, and so on. The chain must not break.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'social-004',
      category: DareCategory.social,
      title: 'Inner Circle',
      description:
          'Whisper something funny to the person on your right. They must whisper it to the next person. Last person says it out loud.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'social-005',
      category: DareCategory.social,
      title: 'Duo Performance',
      description:
          'Pick another player. Together, you must perform a 30-second dramatic scene from a movie the group chooses.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'social-006',
      category: DareCategory.social,
      title: 'Story Time',
      description:
          'Tell the most interesting story about meeting someone new. Keep it under 2 minutes.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'social-007',
      category: DareCategory.social,
      title: 'Tea Spiller',
      description:
          'Share the most interesting piece of gossip you have heard recently. Make it dramatic.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'social-008',
      category: DareCategory.social,
      title: 'Interview Mode',
      description:
          'You are being interviewed by the group. Answer 3 rapid-fire questions from different players. No dodging.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'social-009',
      category: DareCategory.social,
      title: 'Fan Club',
      description:
          'Pick a player. Spend 60 seconds hyping them up like they are a celebrity at a red carpet event.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'social-010',
      category: DareCategory.social,
      title: 'Nickname Game',
      description:
          'Give every other player a new nickname. The group votes on the best one. That nickname is now official.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'social-011',
      category: DareCategory.social,
      title: 'Future Prediction',
      description:
          'Look at each player and make a dramatic future prediction for them. Keep it fun and positive.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'social-012',
      category: DareCategory.social,
      title: 'Love Letter',
      description:
          'Write and read aloud a dramatically romantic love letter to an inanimate object in the room.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'social-013',
      category: DareCategory.social,
      title: 'Appreciation Bomb',
      description:
          'Tell every player one thing you genuinely admire about them. Be specific and heartfelt.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'social-014',
      category: DareCategory.social,
      title: 'Group Photo',
      description:
          'The group must take the most ridiculous group photo possible. Everyone must commit fully.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'social-015',
      category: DareCategory.social,
      title: 'Song Battle',
      description:
          'Pick another player. You each sing 15 seconds of a song. The group votes on the winner.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'social-016',
      category: DareCategory.social,
      title: 'Fake Award Show',
      description:
          'Create and present a fake award for the "Most Likely To" category. Present it to another player with a dramatic speech.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'social-017',
      category: DareCategory.social,
      title: 'Show and Tell',
      description:
          'Show the group the most interesting thing in your pockets or bag. Explain why it matters to you.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'social-018',
      category: DareCategory.social,
      title: 'Hype Man',
      description:
          'You are now the hype man for the next 2 minutes. Every time someone speaks, you must add an enthusiastic comment.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'social-019',
      category: DareCategory.social,
      title: 'Character Introduction',
      description:
          'Introduce yourself as a fictional character. The group asks you 3 questions in character.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'social-020',
      category: DareCategory.social,
      title: 'Double Dare',
      description:
          'Pick a player. You each dare the other to do something. Both must complete their dare.',
      difficulty: DareDifficulty.hard,
    ),

    // ═══════════════════════════════════════════════════════════
    // TRUTH — 20 cards
    // ═══════════════════════════════════════════════════════════
    DareCard(
      id: 'truth-001',
      category: DareCategory.truth,
      title: 'Unpopular Opinion',
      description:
          'Share an opinion you hold that most people disagree with. Defend it for 30 seconds.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'truth-002',
      category: DareCategory.truth,
      title: 'Worst Date',
      description:
          'Tell the group about the worst date you have ever been on. Spare no details.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'truth-003',
      category: DareCategory.truth,
      title: 'Hidden Talent',
      description:
          'Reveal a hidden talent that nobody here knows about. Then demonstrate it.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'truth-004',
      category: DareCategory.truth,
      title: 'Most Embarassing',
      description:
          'What is the most embarrassing thing you have done in public? Tell the full story.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'truth-005',
      category: DareCategory.truth,
      title: 'Celebrity Crush',
      description:
          'Who is your all-time celebrity crush? If you say "I don\'t have one", take a shot.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'truth-006',
      category: DareCategory.truth,
      title: 'Guilty Pleasure',
      description:
          'What is your biggest guilty pleasure? Whether it is food, music, or a TV show, share it.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'truth-007',
      category: DareCategory.truth,
      title: 'First Impression',
      description:
          'Tell the group your honest first impression of the player across from you. Be nice.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'truth-008',
      category: DareCategory.truth,
      title: 'Worst Lie',
      description:
          'What is the worst lie you have ever told? The group gets to judge if it was truly terrible.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'truth-009',
      category: DareCategory.truth,
      title: 'Song Confession',
      description:
          'What song do you secretly love but would never admit to anyone? Sing the chorus.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'truth-010',
      category: DareCategory.truth,
      title: 'Dream Job',
      description:
          'If money was no object, what would you do with your life? Be honest and specific.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'truth-011',
      category: DareCategory.truth,
      title: 'Regret Confession',
      description:
          'What is something you wish you did differently? It does not have to be serious.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'truth-012',
      category: DareCategory.truth,
      title: 'Night Owl',
      description:
          'What is the weirdest thing you have done at 3 AM? If you say "sleep", take a shot.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'truth-013',
      category: DareCategory.truth,
      title: 'Jealousy Check',
      description:
          'What is something you are secretly jealous of about another player? Be specific and kind.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'truth-014',
      category: DareCategory.truth,
      title: 'Deal Breaker',
      description:
          'What is your biggest dating deal breaker? The group votes on whether it is reasonable.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'truth-015',
      category: DareCategory.truth,
      title: 'Superpower Wish',
      description:
          'If you could have one superpower for 24 hours, what would it be and what would you do?',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'truth-016',
      category: DareCategory.truth,
      title: 'Shower Thoughts',
      description:
          'Share the weirdest thought you have had in the shower this week. The group rates it on a scale of 1-10.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'truth-017',
      category: DareCategory.truth,
      title: 'Best Attribute',
      description:
          'What do you think is your best physical attribute? Another player must agree or disagree.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'truth-018',
      category: DareCategory.truth,
      title: 'Why Here',
      description:
          'Be completely honest — why did you agree to play this game tonight? No "it seemed fun" allowed.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'truth-019',
      category: DareCategory.truth,
      title: 'Two Truths',
      description:
          'Tell two truths about yourself. The group guesses which one is a lie. If they are all right, take a shot.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'truth-020',
      category: DareCategory.truth,
      title: 'Rate the Room',
      description:
          'Rate every player at the table on a scale of 1-10 for "vibe". No explanations allowed.',
      difficulty: DareDifficulty.hard,
    ),

    // ═══════════════════════════════════════════════════════════
    // GROUP — 15 cards
    // ═══════════════════════════════════════════════════════════
    DareCard(
      id: 'group-001',
      category: DareCategory.group,
      title: 'Synchronized Dance',
      description:
          'Everyone must perform the same 15-second dance move that you choose. Repeat 3 times in sync.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'group-002',
      category: DareCategory.group,
      title: 'Chain Reaction',
      description:
          'Start a chain reaction. First person sneezes, next person catches it, next person explodes, next person faints.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'group-003',
      category: DareCategory.group,
      title: 'Group Story',
      description:
          'Everyone adds one sentence to a story. No repeating the previous sentence. Go around 3 times.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'group-004',
      category: DareCategory.group,
      title: 'Simon Says',
      description:
          'You are Simon. Give the group 5 rapid "Simon Says" commands. Anyone who messes up takes a shot.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'group-005',
      category: DareCategory.group,
      title: 'Musical Chairs',
      description:
          'Everyone except you must stand up and switch seats before you sit back down. You try to grab a seat.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'group-006',
      category: DareCategory.group,
      title: 'Frozen Silly',
      description:
          'Everyone must freeze in a silly pose. You walk around and judge the best and worst pose.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'group-007',
      category: DareCategory.group,
      title: 'Group Vote',
      description:
          'The group must reach a consensus on a topic you choose. You have 60 seconds. No one can repeat what someone else said.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'group-008',
      category: DareCategory.group,
      title: 'Team Challenge',
      description:
          'Split into two teams and have a 30-second thumb war tournament. Losing team takes a shot.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'group-009',
      category: DareCategory.group,
      title: 'Impression Contest',
      description:
          'Everyone must do an impression of the same celebrity or character. The group votes on the best one.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'group-010',
      category: DareCategory.group,
      title: 'Staring Contest',
      description:
          'All players pair up for a staring contest. Last person standing in each pair wins. Losers take a shot.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'group-011',
      category: DareCategory.group,
      title: 'Paper Plane Race',
      description:
          'Everyone makes a paper airplane. Race them. Last place takes a shot.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'group-012',
      category: DareCategory.group,
      title: 'Would You Rather',
      description:
          'Everyone answers 3 "Would You Rather" questions. No repeats. Anyone who hesitates more than 5 seconds takes a shot.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'group-013',
      category: DareCategory.group,
      title: 'Silent Disco',
      description:
          'Everyone dances for 30 seconds without music. The group judges the best dancer.',
      difficulty: DareDifficulty.easy,
    ),
    DareCard(
      id: 'group-014',
      category: DareCategory.group,
      title: 'Emoji Charades',
      description:
          'Everyone acts out a scenario using only gestures. No words allowed. The group guesses.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'group-015',
      category: DareCategory.group,
      title: 'Speed Debate',
      description:
          'Pick a silly topic. Two players debate it for 30 seconds each. The group votes on the winner.',
      difficulty: DareDifficulty.medium,
    ),

    // ═══════════════════════════════════════════════════════════
    // CHAOS — 10 cards
    // ═══════════════════════════════════════════════════════════
    DareCard(
      id: 'chaos-001',
      category: DareCategory.chaos,
      title: 'Spin the Caller',
      description:
          'You become the game host for the next round. Make the most chaotic decisions you can.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'chaos-002',
      category: DareCategory.chaos,
      title: 'Reverse Card',
      description:
          'Everyone must do the opposite of what you say for 2 minutes. If you say "stand up", they sit down.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'chaos-003',
      category: DareCategory.chaos,
      title: 'Role Swap',
      description:
          'Swap seats with the player across from you and adopt their persona for 2 minutes.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'chaos-004',
      category: DareCategory.chaos,
      title: 'Random Act',
      description:
          'Another player picks any action. You must do it. No questions asked. The action must be safe and legal.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'chaos-005',
      category: DareCategory.chaos,
      title: 'Chaos Coordinator',
      description:
          'You get to assign everyone a random silly task. They must complete it before the next round starts.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'chaos-006',
      category: DareCategory.chaos,
      title: 'Reality Shift',
      description:
          'Announce a new "rule" for the game. The group votes on whether it stays. If it stays, it lasts for 3 rounds.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'chaos-007',
      category: DareCategory.chaos,
      title: 'Pick Your Poison',
      description:
          'Pick 3 challenges from a hat. You must complete all of them before your next turn.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'chaos-008',
      category: DareCategory.chaos,
      title: 'Clock is Ticking',
      description:
          'You have 30 seconds to make the person to your left laugh. If they laugh, you win. If they don\'t, take a shot.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'chaos-009',
      category: DareCategory.chaos,
      title: 'Switcheroo',
      description:
          'Quickly swap roles with any player. You become them for the next round, and they become you.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'chaos-010',
      category: DareCategory.chaos,
      title: 'Wild Card',
      description:
          'You set the next dare for another player. Make it good. The group must approve.',
      difficulty: DareDifficulty.hard,
    ),

    // ═══════════════════════════════════════════════════════════
    // WILD — 10 cards
    // ═══════════════════════════════════════════════════════════
    DareCard(
      id: 'wild-001',
      category: DareCategory.wild,
      title: 'Plot Twist',
      description:
          'Choose another player. You must dramatically announce a fake plot twist about their life. The more absurd, the better.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'wild-002',
      category: DareCategory.wild,
      title: 'Time Traveler',
      description:
          'Pretend you are from the year 2050. Describe how ridiculous the "ancient year" of 2025 was. Be dramatic.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'wild-003',
      category: DareCategory.wild,
      title: 'Alternate Universe',
      description:
          'Create an alternate version of another player at the table. Describe their "evil twin" in detail.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'wild-004',
      category: DareCategory.wild,
      title: 'Dramatic Reading',
      description:
          'Read the nearest text (menu, label, receipt) as if it is the most dramatic Shakespeare scene ever performed.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'wild-005',
      category: DareCategory.wild,
      title: 'Speed Relationship',
      description:
          'Pick a player. You have 60 seconds to plan your "fake wedding". Include vows, guest list, and honeymoon destination.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'wild-006',
      category: DareCategory.wild,
      title: 'Conspiracy Theory',
      description:
          'Come up with the most ridiculous conspiracy theory about another player. Convince the group it might be true.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'wild-007',
      category: DareCategory.wild,
      title: 'Animal Instincts',
      description:
          'Choose an animal. For the next 2 minutes, you can only communicate using that animal\'s sounds and gestures.',
      difficulty: DareDifficulty.medium,
    ),
    DareCard(
      id: 'wild-008',
      category: DareCategory.wild,
      title: 'Shakespeare Mode',
      description:
          'Everything you say for the next 2 minutes must be in iambic pentameter. The group judges your meter.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'wild-009',
      category: DareCategory.wild,
      title: 'Super Villain',
      description:
          'Stand up and deliver your super villain monologue. Explain your evil plan to take over the world. Dramatic gestures required.',
      difficulty: DareDifficulty.hard,
    ),
    DareCard(
      id: 'wild-010',
      category: DareCategory.wild,
      title: 'Motivational Speaker',
      description:
          'Deliver a 60-second motivational speech about why the table should keep playing. Make it so inspiring that everyone claps.',
      difficulty: DareDifficulty.hard,
    ),
  ];

  /// Creates a new shuffled [DareDeck] with all cards.
  static DareDeck newDeck({Random? random}) {
    return DareDeck(allCards, random: random);
  }
}
