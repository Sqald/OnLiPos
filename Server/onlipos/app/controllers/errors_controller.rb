class ErrorsController < ActionController::Base
  layout "error"

  ERROR_DETAILS = {
    400 => { title: "Bad Request",                       ja: "リクエストの形式が正しくありません。",                                  category: :client },
    401 => { title: "Unauthorized",                      ja: "認証が必要です。ログインしてから再度お試しください。",                    category: :client },
    402 => { title: "Payment Required",                  ja: "この操作には支払いが必要です。",                                        category: :client },
    403 => { title: "Forbidden",                         ja: "このページへのアクセス権がありません。",                                  category: :client },
    404 => { title: "Not Found",                         ja: "お探しのページが見つかりません。URLを確認してください。",                  category: :client },
    405 => { title: "Method Not Allowed",                ja: "このリクエストメソッドは許可されていません。",                            category: :client },
    406 => { title: "Not Acceptable",                    ja: "サーバーが対応できるコンテンツ形式が見つかりません。",                    category: :client },
    407 => { title: "Proxy Authentication Required",     ja: "プロキシ認証が必要です。",                                              category: :client },
    408 => { title: "Request Timeout",                   ja: "リクエストがタイムアウトしました。しばらくしてから再度お試しください。",  category: :client },
    409 => { title: "Conflict",                          ja: "リクエストが現在のサーバー状態と競合しています。",                        category: :client },
    410 => { title: "Gone",                              ja: "このリソースは恒久的に削除されました。",                                  category: :client },
    411 => { title: "Length Required",                   ja: "Content-Length ヘッダーが必要です。",                                   category: :client },
    412 => { title: "Precondition Failed",               ja: "リクエストの前提条件が満たされていません。",                              category: :client },
    413 => { title: "Content Too Large",                 ja: "送信データが大きすぎます。ファイルサイズを確認してください。",            category: :client },
    414 => { title: "URI Too Long",                      ja: "リクエストURIが長すぎます。",                                           category: :client },
    415 => { title: "Unsupported Media Type",            ja: "サーバーが対応していないメディアタイプです。",                           category: :client },
    416 => { title: "Range Not Satisfiable",             ja: "指定されたRange が満たせません。",                                      category: :client },
    417 => { title: "Expectation Failed",                ja: "Expectヘッダーの要求をサーバーが満たせません。",                         category: :client },
    418 => { title: "I'm a Teapot",                      ja: "私はティーポットです。コーヒーを淹れることはできません。",                category: :client },
    421 => { title: "Misdirected Request",               ja: "リクエストが不適切なサーバーに送信されました。",                         category: :client },
    422 => { title: "Unprocessable Content",             ja: "リクエストの内容が処理できません。入力内容を確認してください。",          category: :client },
    423 => { title: "Locked",                            ja: "リソースがロックされています。",                                         category: :client },
    424 => { title: "Failed Dependency",                 ja: "前のリクエストが失敗したため、このリクエストも失敗しました。",            category: :client },
    425 => { title: "Too Early",                         ja: "サーバーがリクエストを処理する準備ができていません。",                    category: :client },
    426 => { title: "Upgrade Required",                  ja: "プロトコルのアップグレードが必要です。",                                  category: :client },
    428 => { title: "Precondition Required",             ja: "このリクエストには前提条件が必要です。",                                  category: :client },
    429 => { title: "Too Many Requests",                 ja: "リクエストが多すぎます。しばらく時間をおいてから再度お試しください。",    category: :client },
    431 => { title: "Request Header Fields Too Large",   ja: "リクエストヘッダーが大きすぎます。",                                    category: :client },
    451 => { title: "Unavailable For Legal Reasons",     ja: "法的な理由によりこのコンテンツは利用できません。",                       category: :client },
    500 => { title: "Internal Server Error",             ja: "サーバー内部でエラーが発生しました。しばらくしてから再度お試しください。", category: :server },
    501 => { title: "Not Implemented",                   ja: "この機能はサーバーで実装されていません。",                               category: :server },
    502 => { title: "Bad Gateway",                       ja: "ゲートウェイが無効なレスポンスを受け取りました。",                       category: :server },
    503 => { title: "Service Unavailable",               ja: "サービスが一時的に利用できません。メンテナンス中の可能性があります。",    category: :server },
    504 => { title: "Gateway Timeout",                   ja: "ゲートウェイがタイムアウトしました。",                                   category: :server },
    505 => { title: "HTTP Version Not Supported",        ja: "サーバーがリクエストのHTTPバージョンに対応していません。",                category: :server },
    506 => { title: "Variant Also Negotiates",           ja: "サーバー設定エラーが発生しました。",                                    category: :server },
    507 => { title: "Insufficient Storage",              ja: "サーバーのストレージが不足しています。",                                 category: :server },
    508 => { title: "Loop Detected",                     ja: "サーバーがリクエストの処理中に無限ループを検出しました。",               category: :server },
    510 => { title: "Not Extended",                      ja: "リクエストの拡張情報が不足しています。",                                 category: :server },
    511 => { title: "Network Authentication Required",   ja: "ネットワークへのアクセスに認証が必要です。",                             category: :server },
  }.freeze

  def show
    status_param = params[:status].to_i
    @status_code = ERROR_DETAILS.key?(status_param) ? status_param : 500
    @error_info  = ERROR_DETAILS[@status_code]
    render "errors/show", formats: [:html], layout: "error", status: @status_code
  end

  def index
    @client_errors = ERROR_DETAILS.select { |_, v| v[:category] == :client }
    @server_errors = ERROR_DETAILS.select { |_, v| v[:category] == :server }
    render "errors/index", formats: [:html], layout: "error", status: :ok
  end
end
