/* =====================================================================
   Курсова робота NVBD, варіант 6 «Поліклініка»
   Скрипт 1. Створення бази даних PolyclinicDB (OLTP)
   УВАГА: якщо БД вже існує, вона буде видалена та створена заново.
   ===================================================================== */
USE master;
GO

IF DB_ID(N'PolyclinicDB') IS NOT NULL
BEGIN
    ALTER DATABASE PolyclinicDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PolyclinicDB;
END
GO

-- Колація збігається з колацією сервера (і tempdb) — без конфліктів у тимчасових таблицях
CREATE DATABASE PolyclinicDB COLLATE Ukrainian_CI_AS;
GO

-- Початковий розмір файлів під ~3.5 млн записів, щоб уникнути частого авторозширення
ALTER DATABASE PolyclinicDB MODIFY FILE (NAME = N'PolyclinicDB',     SIZE = 1024MB, FILEGROWTH = 256MB);
ALTER DATABASE PolyclinicDB MODIFY FILE (NAME = N'PolyclinicDB_log', SIZE = 512MB,  FILEGROWTH = 256MB);
GO

-- Навчальне середовище з масовим завантаженням: мінімальне журналювання
ALTER DATABASE PolyclinicDB SET RECOVERY SIMPLE;
GO
