# 契約アカウント配下のマスタ（クーポン・仕入先など）の一覧・登録・変更・削除を共通化した基底クラス。
# 画面は app/views/dashboard/resources を使う。継承先で manages を呼び、列と入力項目を定義する。
#
#   columns: { "見出し" => ->(record, view) { 表示内容 } }
#   fields:  [ Field.new(属性, "ラベル", 種類, オプション) ]   種類: text / number / date / time / textarea / checkbox / select / checkboxes
class Dashboard::ResourceController < Dashboard::BaseController
  Field = Struct.new(:name, :label, :type, :options, keyword_init: true)

  class_attribute :resource_config
  helper_method :resource_config, :field_choices

  def self.manages(model, title:, columns:, fields:, association: model.model_name.plural, description: nil, order: :id, search: nil)
    self.resource_config = { model: model, title: title, columns: columns, fields: fields, association: association, description: description, order: order, search: search }
  end

  def self.field(name, label, type = :text, **options) = Field.new(name: name, label: label, type: type, options: options)

  before_action :set_record, only: [ :edit, :update, :destroy ]

  def index
    @records = filtered_scope.order(resource_config[:order]).page(params[:page]).per(50)
    render "dashboard/resources/index"
  end

  def new
    @record = scope.build
    render "dashboard/resources/form"
  end

  def create
    @record = scope.build(record_params)
    save_and_respond("#{resource_config[:title]}を登録しました。")
  end

  def edit
    render "dashboard/resources/form"
  end

  def update
    @record.assign_attributes(record_params)
    save_and_respond("#{resource_config[:title]}を変更しました。")
  end

  def destroy
    if @record.destroy
      redirect_to({ action: :index }, notice: "削除しました。", status: :see_other)
    else
      redirect_to({ action: :index }, alert: @record.errors.full_messages.join("、").presence || "利用履歴があるため削除できません。", status: :see_other)
    end
  rescue ActiveRecord::InvalidForeignKey
    redirect_to({ action: :index }, alert: "利用履歴があるため削除できません。", status: :see_other)
  end

  private

  def scope = current_account.public_send(resource_config[:association])
  def filtered_scope = scope

  def set_record
    @record = scope.find(params[:id])
  end

  def save_and_respond(message)
    if @record.save
      redirect_to({ action: :index }, notice: message, status: :see_other)
    else
      render "dashboard/resources/form", status: :unprocessable_entity
    end
  end

  def record_params
    lists, scalars = resource_config[:fields].partition { |f| f.type == :checkboxes }
    permitted = params.require(resource_config[:model].model_name.param_key).permit(*scalars.map(&:name), lists.to_h { |f| [ f.name, [] ] })
    lists.each { |f| permitted[f.name] = Array(permitted[f.name]).compact_blank if permitted.key?(f.name) }
    restrict_associations(permitted)
  end

  # 選択肢にない関連（他の契約のレコード）を指定できないようにする
  def restrict_associations(permitted)
    resource_config[:fields].each do |f|
      next unless f.options[:choices] && permitted[f.name].present? && f.name.to_s.match?(/_ids?\z/)

      allowed = field_choices(f).map { |_, value| value.to_s }
      values = Array(permitted[f.name]).map(&:to_s) & allowed
      permitted[f.name] = f.type == :checkboxes ? values : values.first
    end
    permitted
  end

  def field_choices(field)
    choices = field.options[:choices]
    choices.respond_to?(:call) ? instance_exec(&choices) : choices
  end
end
