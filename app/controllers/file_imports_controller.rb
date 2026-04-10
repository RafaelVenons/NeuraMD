# frozen_string_literal: true

class FileImportsController < ApplicationController
  def index
    @imports = policy_scope(FileImport).recent.limit(50)
  end

  def new
    @import = FileImport.new
    authorize @import
  end

  def create
    @import = FileImport.new(import_params)
    @import.user = current_user
    @import.status = "pending"
    @import.original_filename = @import.source_file&.filename.to_s
    authorize @import

    if @import.save
      FileImports::ProcessJob.perform_later(@import.id)
      redirect_to file_import_path(@import), notice: "Arquivo enviado. Conversão iniciada."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @import = FileImport.find(params[:id])
    authorize @import
  end

  private

  def import_params
    params.require(:file_import).permit(:source_file, :base_tag, :import_tag, :extra_tags, :split_level)
  end
end
