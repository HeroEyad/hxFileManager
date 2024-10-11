#include <iostream>
#include <filesystem>
#include <chrono>
#include <ctime>

namespace fs = std::filesystem;

extern "C"
{
    void move_directory(const char *sourcePath, const char *destPath)
    {
        try
        {
            fs::rename(sourcePath, destPath);
            std::cout << "Directory moved from " << sourcePath << " to " << destPath << std::endl;
        }
        catch (const fs::filesystem_error &e)
        {
            std::cerr << "Error moving directory: " << e.what() << std::endl;
        }
    }

    void delete_file(const char *filePath)
    {
        try
        {
            fs::remove(filePath);
            std::cout << "File deleted: " << filePath << std::endl;
        }
        catch (const fs::filesystem_error &e)
        {
            std::cerr << "Error deleting file: " << e.what() << std::endl;
        }
    }

    // Function to rename a folder
    void rename_folder(const char *oldPath, const char *newPath)
    {
        try
        {
            fs::rename(oldPath, newPath); // Use rename for both files and folders
            std::cout << "Folder renamed from " << oldPath << " to " << newPath << std::endl;
        }
        catch (const fs::filesystem_error &e)
        {
            std::cerr << "Error renaming folder: " << e.what() << std::endl;
        }
    }

    // New function to copy a file
    void copy(const char *sourcePath, const char *destPath)
    {
        try
        {
            fs::copy(sourcePath, destPath, fs::copy_options::overwrite_existing);
            std::cout << "File copied from " << sourcePath << " to " << destPath << std::endl;
        }
        catch (const fs::filesystem_error &e)
        {
            std::cerr << "Error copying file: " << e.what() << std::endl;
        }
    }

    // New function to copy a directory recursively
    void copy_directory(const char *sourcePath, const char *destPath)
    {
        try
        {
            fs::copy(sourcePath, destPath, fs::copy_options::recursive | fs::copy_options::overwrite_existing);
            std::cout << "Directory copied from " << sourcePath << " to " << destPath << std::endl;
        }
        catch (const fs::filesystem_error &e)
        {
            std::cerr << "Error copying directory: " << e.what() << std::endl;
        }
    }

    /*void get_file_info(const char *filePath)
    {
        try
        {
            fs::path path(filePath);
            if (fs::exists(path))
            {
                auto size = fs::file_size(path);
                auto last_write_time = fs::last_write_time(path);

                // Convert file_time_type to time_t
                auto cftime = decltype(last_write_time)::clock::to_time_t(last_write_time);

                std::cout << "File: " << filePath << std::endl;
                std::cout << "Size: " << size << " bytes" << std::endl;
                std::cout << "Last modified: " << std::ctime(&cftime);
            }
            else
            {
                std::cerr << "File does not exist: " << filePath << std::endl;
            }
        }
        catch (const fs::filesystem_error &e)
        {
            std::cerr << "Error getting file info: " << e.what() << std::endl;
        }
    }*/
}
