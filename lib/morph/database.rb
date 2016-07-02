module Morph
  class Database
    def initialize(data_path)
      @data_path = data_path
    end

    def self.sqlite_db_filename
      'data.sqlite'
    end

    def self.sqlite_db_backup_filename
      "#{sqlite_db_filename}.backup"
    end

    def self.sqlite_table_name
      'data'
    end

    def sqlite_db_path
      File.join(@data_path, Database.sqlite_db_filename)
    end

    def sqlite_db_backup_path
      File.join(@data_path, Database.sqlite_db_backup_filename)
    end

    def backup
      return unless File.exist?(sqlite_db_path)

      FileUtils.cp(sqlite_db_path, sqlite_db_backup_path)
    end

    # The actual table names in the current db
    def table_names
      q = sql_query_safe("select name from sqlite_master where type='table'")
      if q
        q = q.map { |h| h['name'] }
        # sqlite_sequence is a special system table (used with autoincrement)
        q.delete('sqlite_sequence')
        q
      else
        []
      end
    end

    def valid?
      # Do any old query
      table_names
      true
    rescue SQLite3::NotADatabaseException
      false
    end

    # The table that should be listed first because it is the most important
    def first_table_name
      if table_names.include?(Database.sqlite_table_name)
        Database.sqlite_table_name
      else
        table_names.first
      end
    end

    def sql_query(query, readonly = true)
      fail SQLite3::Exception, 'No query specified' if query.blank?
      SQLite3::Database.new(
        sqlite_db_path,
        results_as_hash: true,
        type_translation: true,
        readonly: readonly) do |db|
        # If database is busy wait 5s
        db.busy_timeout(5000)
        return Database.clean_utf8_query_result(db.execute(query))
      end
    end

    def self.clean_utf8_query_result(array)
      array.map { |row| clean_utf8_query_row(row) }
    end

    def self.clean_utf8_query_row(row)
      result = {}
      row.each { |k, v| result[clean_utf8_string(k)] = clean_utf8_string(v) }
      result
    end

    # Removes bits of strings that are invalid UTF8
    def self.clean_utf8_string(string)
      if string.respond_to?(:encode)
        if string.valid_encoding?
          # Actually try converting to utf-8 and check if that works
          begin
            string.encode('utf-8')
          rescue Encoding::UndefinedConversionError
            convert_to_utf8_and_clean_binary_string(string)
          end
        else
          convert_to_utf8_and_clean_binary_string(string)
        end
      else
        string
      end
    end

    # This is what we use when we don't know what the encoding of the string
    # is. This assumes little about the string encoding and cleans the result
    # when converting to utf-8. Using this is a last resort when simple
    # conversions aren't working.
    def self.convert_to_utf8_and_clean_binary_string(string)
      string.encode('UTF-8', 'binary',
                    invalid: :replace, undef: :replace, replace: '')
    end

    def sql_query_safe(query, readonly = true)
      sql_query(query, readonly)
    rescue SQLite3::CantOpenException, SQLite3::SQLException
      nil
    end

    # Returns 0 if table doesn't exists (or there is some other problem)
    def no_rows(table = table_names.first)
      q = sql_query_safe("select count(*) from '#{table}'")
      q ? q.first.values.first : 0
    rescue SQLite3::NotADatabaseException, SQLite3::CorruptException
      0
    end

    def sqlite_db_size
      if File.exist?(sqlite_db_path)
        File::Stat.new(sqlite_db_path).size
      else
        0
      end
    end

    def table_names_safe
      table_names
    rescue SQLite3::NotADatabaseException
      []
    end

    # Total number of records across all tables
    def sqlite_total_rows
      table_names_safe.map { |t| no_rows(t) }.sum
    end

    def clear
      FileUtils.rm sqlite_db_path if File.exist?(sqlite_db_path)
    end

    def write_sqlite_database(content)
      FileUtils.mkdir_p @data_path
      File.open(sqlite_db_path, 'wb') { |file| file.write(content) }
    end

    def standardise_table_name(table_name)
      sql_query_safe("ALTER TABLE '#{table_name}' " \
        "RENAME TO '#{Database.sqlite_table_name}'", false)
    end

    def select_first_ten(table = table_names.first)
      "select * from '#{table}' limit 10"
    end

    def select_all(table = table_names.first)
      "select * from '#{table}'"
    end

    def first_ten_rows(table = table_names.first)
      r = sql_query_safe(select_first_ten(table))
      r ? r : []
    end

    def self.tidy_data_path(data_path)
      # First get all the files in the data directory
      filenames = Dir.entries(data_path)
      filenames.delete('.')
      filenames.delete('..')
      filenames.delete(sqlite_db_filename)
      FileUtils.rm_rf filenames.map { |f| File.join(data_path, f) }
    end

    # Remove any files or directories in the data_path that are not the
    # actual database
    def tidy_data_path
      Database.tidy_data_path(@data_path)
    end
  end
end
