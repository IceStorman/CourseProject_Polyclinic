IF SUSER_ID(N'NT Service\MSSQLServerOLAPService') IS NULL
    CREATE LOGIN [NT Service\MSSQLServerOLAPService] FROM WINDOWS;
GO
USE PolyclinicDW;
GO
IF USER_ID(N'NT Service\MSSQLServerOLAPService') IS NULL
    CREATE USER [NT Service\MSSQLServerOLAPService] FOR LOGIN [NT Service\MSSQLServerOLAPService];
ALTER ROLE db_datareader ADD MEMBER [NT Service\MSSQLServerOLAPService];
GO
