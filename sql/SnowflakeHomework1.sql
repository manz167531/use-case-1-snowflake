CREATE DATABASE RABBIT_ECOMERSE_DB;
USE RABBIT_ECOMERSE_DB;

CREATE OR REPLACE SCHEMA STAGE_EXTERNAL;

CREATE STAGE RABBIT_ECOMERSE_DB.STAGE_EXTERNAL.ecommerce_orders;

//LIST @RABBIT_ECOMERSE_DB.STAGE_EXTERNAL.ecommerce_orders;

CREATE OR REPLACE TABLE td_ecommerce_orders
AS
SELECT $1 as Order_ID,
       $2 as Customer_ID,
       $3 AS Customer_Name,
       $4 as Order_Date,
       $5 as Product, 
       $6 as Quantity,
       $7 as Price,
       $8 as Discount,
       $9 as Total_Amount,
       $10 as Payment_Method,
       $11 as Shipping_Address,
       $12 as Status
FROM @RABBIT_ECOMERSE_DB.STAGE_EXTERNAL.ecommerce_orders/ecommerce_orders.csv
where 1=2;

//SELECT * FROM td_ecommerce_orders

//LIST @RABBIT_ECOMERSE_DB.STAGE_EXTERNAL.ecommerce_orders;

COPY INTO td_ecommerce_orders
FROM (
SELECT $1 as Order_ID,
       $2 as Customer_ID,
       $3 AS Customer_Name,
       $4 as Order_Date,
       $5 as Product, 
       $6 as Quantity,
       $7 as Price,
       $8 as Discount,
       $9 as Total_Amount,
       $10 as Payment_Method,
       $11 as Shipping_Address,
       $12 as Status
FROM @RABBIT_ECOMERSE_DB.STAGE_EXTERNAL.ecommerce_orders/ecommerce_orders.csv
)
FILE_FORMAT = (TYPE = CSV, SKIP_HEADER = 1)

FORCE = TRUE;


//КОРИГИРАНЕ НА ЛИПСВАЩИ ДАННИ
//ТАМ КЪДЕТО СТЕ ПИСАЛИ ДУМАТА "прехвърлете" СЪМ ИЗТРИВАЛ ЗАПИСА ОТ ГОЛЯМАТА ТАБЛИЦА И СЪМ ГО ОСТАВЯЛ САМО В МАЛКАТА
SELECT * FROM td_ecommerce_orders;


CREATE OR REPLACE TABLE td_for_review LIKE td_ecommerce_orders;

INSERT INTO td_for_review
SELECT *
FROM RABBIT_ECOMERSE_DB.STAGE_EXTERNAL.td_ecommerce_orders
WHERE Shipping_Address IS NULL AND Status = 'Delivered';

//SELECT * FROM td_for_review;

DELETE FROM td_ecommerce_orders 
WHERE Shipping_Address IS NULL AND Status = 'Delivered';


CREATE OR REPLACE TABLE td_suspisios_records LIKE td_ecommerce_orders;
//Ако в записа липсва данни за клиента Customer_id , то тогава този запис трябва да бъде прехвърлен към таблица td_suspisios_records
//ГОСПОДИНЕ ТУК ПРЕДПОЛАГАМ СТЕ СЕ ОБЪРКАЛИ В УСЛОВИЕТО ТЪЙ КАТО НЯМА ПРАЗЕН CUSTOMER_ID, НО ИМА НЕПОПЪЛНЕНИ ИМЕНА - CUSTOMER_NAME ЗАТОВА ТОВА ПОДУСЛОВИЕ СЪМ ГО ИЗПЪЛНИЛ СПРЯМО ТАЗИ КОЛОНА

//SELECT * FROM TD_ECOMMERCE_ORDERS WHERE CUSTOMER_NAME IS NULL

INSERT INTO TD_SUSPISIOS_RECORDS
SELECT * FROM TD_ECOMMERCE_ORDERS
WHERE CUSTOMER_NAME IS NULL;

DELETE FROM TD_ECOMMERCE_ORDERS 
WHERE CUSTOMER_NAME IS NULL;

//SELECT * FROM TD_ECOMMERCE_ORDERS WHERE PAYMENT_METHOD IS NULL;
UPDATE TD_ECOMMERCE_ORDERS
SET Payment_Method = 'Unknown'
WHERE Payment_Method IS NULL;
//SELECT * FROM TD_ECOMMERCE_ORDERS WHERE PAYMENT_METHOD='Unknown';


//НЕВАЛИДЕН ФОРМАТ НА ДАННИТЕ
//ПРИЕМАМ ЧЕ 'YYYY-MM-DD' СА НЕКОРЕКТНИТЕ ТИП ДАТИ И ГИ ЗАМЕНЯМ С 'MM/DD/YYYY', ВСЕКИ ПЪТ КАТО СРЕЩНА НЕКОРЕКТНА ДАТА Я ЗАМЕНЯМ С '07/11/1864'
CREATE OR REPLACE TABLE td_invalid_date_format LIKE td_ecommerce_orders;

INSERT INTO td_invalid_date_format
SELECT * FROM TD_ECOMMERCE_ORDERS
WHERE TRY_TO_DATE(order_date, 'MM/DD/YYYY') IS NULL;

//SELECT * FROM TD_INVALID_DATE_FORMAT;

UPDATE TD_ECOMMERCE_ORDERS
SET ORDER_DATE = '07/11/1864'
WHERE ORDER_DATE NOT RLIKE '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$'; --за този шаблон chatGPT удари едно рамо 


//ОТРИЦАТЕЛНИ ИЛИ НЕНУЛЕВИ СТОЙНОСТИ ЗА КОЛИЧЕСТО И СТРАНА

//ГОСПОДИНЕ ТУК СЪЩО ПРЕДПОЛАГАМ ИМА НЯКАКВА ОБЪРКВАЦИЯ ТЪЙ КАТО ИСКАТЕ ОТ НАС ДА ПРОВЕРИМ ЗА ОТРИЦАТЕЛНА ЦЕНА НО ТАКАВА НИКЪДЕ НЕ СЕ СРЕЩА В ТАБЛИЦАТА
//ВСЕ ПАК СЪМ НАПИСАЛ НУЖНАТА ПРОВЕРКА
CREATE TABLE INVALID_VALUES LIKE TD_ECOMMERCE_ORDERS;

INSERT INTO INVALID_VALUES 
SELECT * FROM TD_ECOMMERCE_ORDERS 
WHERE QUANTITY <= 0 OR PRICE <= 0;

DELETE FROM TD_ECOMMERCE_ORDERS 
WHERE QUANTITY <= 0 OR PRICE <= 0;

select * from invalid_values where price <=0;


//НЕВАЛИДНА ОТСТЪПКА
UPDATE TD_ECOMMERCE_ORDERS
SET Discount = 
    CASE 
        WHEN Discount < 0.0 THEN 0.0
        WHEN Discount > 0.5 THEN 0.5
        ELSE Discount
    END;
    
//SELECT DISCOUNT FROM TD_ECOMMERCE_ORDERS WHERE DISCOUNT>0.5 OR DISCOUNT<0;


//НЕПРАВИЛНО КАЛКУЛИРАНА ЦЕНА
UPDATE TD_ECOMMERCE_ORDERS
SET Total_Amount = Quantity * Price * (1 - Discount);


//НЕКОНСИСТЕНТИ СТАТУСИ НА ПОРЪЧКАТА
//ТЪЙ КАТО ПО РАНО ИЗТРИХ ТЕЗИ ЗАПИСИ ТАЗИ ЗАЯВКА НЕ ОБРАБОТВА НИЩО НО СЪМ ПОЛОЖИТЕЛЕН ЧЕ Е ПРАВИЛНА ГОСПОДИНЕ ТАКА ЧЕ МОЛЯ ДА Я ЗАЧЕТЕТЕ
UPDATE TD_ECOMMERCE_ORDERS
SET STATUS = 'Pending'
WHERE STATUS = 'Delivered' AND SHIPPING_ADDRESS IS NULL; 

//------------------------------------------------------------------------
CREATE TABLE UPDATED_TD_FOR_REVIEW LIKE TD_FOR_REVIEW;
INSERT INTO UPDATED_TD_FOR_REVIEW SELECT * FROM TD_FOR_REVIEW;
UPDATE UPDATED_TD_FOR_REVIEW
SET STATUS = 'Pending'
WHERE STATUS = 'Delivered' AND SHIPPING_ADDRESS IS NULL;
//------------------------------------------------------------------------


//ДУПЛИЦИРАНИ РЕДОВЕ
CREATE TABLE td_clean_records LIKE td_ecommerce_orders;

INSERT INTO RABBIT_ECOMERSE_DB.STAGE_EXTERNAL.TD_CLEAN_RECORDS
SELECT *
FROM ( SELECT DISTINCT * 
    FROM RABBIT_ECOMERSE_DB.STAGE_EXTERNAL.TD_ECOMMERCE_ORDERS
);




