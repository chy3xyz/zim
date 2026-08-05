class Agents {
  final int total;
  final List<Agent> agents;

  Agents({required this.total, required this.agents});

  factory Agents.fromJson(Map<String, dynamic> json) {
    return Agents(
      total: json['total'],
      agents: json['agents'] == null ? [] : List<Agent>.from(json['agents'].map((x) => Agent.fromJson(x))),
    );
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['total'] = total;
    data['agents'] = agents.map((v) => v.toJson()).toList();

    return data;
  }
}

class Agent {
  final String? userID;
  final String nickname;
  final String? faceURL;
  final String url;
  final String key;
  final String? identity;
  final String model;
  final String? prompts;
  final int? createTime;

  Agent({
    this.userID,
    required this.nickname,
    this.faceURL,
    required this.url,
    required this.key,
    this.identity,
    required this.model,
    this.prompts,
    this.createTime,
  });

  factory Agent.fromJson(Map<String, dynamic> json) {
    return Agent(
      userID: json['userID'],
      nickname: json['nickname'],
      faceURL: json['faceURL'],
      url: json['url'],
      key: json['key'],
      identity: json['identity'],
      model: json['model'],
      prompts: json['prompts'],
      createTime: json['createTime'],
    );
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['userID'] = userID;
    data['nickname'] = nickname;
    data['faceURL'] = faceURL;
    data['url'] = url;
    data['key'] = key;
    data['identity'] = identity;
    data['model'] = model;
    data['prompts'] = prompts;
    data['createTime'] = createTime;

    return data;
  }
}
